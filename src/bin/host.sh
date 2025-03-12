#!/usr/bin/env bash

## ENV VARS

export DOCKER_CLI_HINTS=false

## LIBS

. "${HOME}/.solos/repo/src/shared/lib.universal.sh" || exit 1
. "${HOME}/.solos/repo/src/shared/log.universal.sh" || exit 1

## GLOBAL VARIABLES

# Base directories.
host__repo_dir="${HOME}/.solos/repo"
host__data_dir="${HOME}/.solos/data"
host__plugins_dir="${HOME}/.solos/plugins"
host__plugins_manifest_file="${host__plugins_dir}/solos.manifest.json"
# RC files.
host__user_bashrc_file="${HOME}/.solos/rcfiles/.bashrc"
# Docker stuff.
host__base_dockerfile="${host__repo_dir}/src/Dockerfile"
host__project_fallback_dockerfile="${host__repo_dir}/src/Dockerfile.project"
host__base_docker_image="solos:latest"
host__project_docker_image="solos-checked-out-project:latest"
host__project_docker_container="solos-checked-out-project"
# Paths specific to the docker FS.
host__containerized_bin_path="/root/.solos/repo/src/bin/container.sh"
# Files used to communicated information between the host and the container.
host__data_store_users_home_dir_file="${host__data_dir}/store/users_home_dir"
host__data_cli_dir_master_log_file="${host__data_dir}/cli/master.log"
host__data_cli_dir_built_project_file="${host__data_dir}/cli/built_project"
host__data_cli_dir_built_project_from_dockerfile_file="${host__data_dir}/cli/built_project_from"

mkdir -p "${host__data_dir}/store"
mkdir -p "${host__data_dir}/cli"
mkdir -p "${host__data_dir}/panics"
mkdir -p "${host__plugins_dir}"
if [[ ! -f "${host__plugins_manifest_file}" ]]; then
  echo "[]" >"${host__plugins_manifest_file}"
fi

## LOGGING

log.use "${host__data_cli_dir_master_log_file}"
host.log_success() {
  log.success "(CLI:HOST) ${1}"
}
host.log_info() {
  log.info "(CLI:HOST) ${1}"
}
host.log_warn() {
  log.warn "(CLI:HOST) ${1}"
}
host.log_error() {
  log.error "(CLI:HOST) ${1}"
}

## UTILS

host.get_project_dockerfile() {
  local target_project="${1}"
  echo "${HOME}/.solos/projects/${target_project}/Dockerfile"
}
host.get_project_vscode_workspace_file() {
  local target_project="${1}"
  echo "${HOME}/.solos/projects/${target_project}/.vscode/${target_project}.code-workspace"
}
# We want rebuilds to happen under the following conditions:
# 1) The user has never built a project before.
# 2) The project is different from the one that was last built.
# 3) The project was not checked out before but now it is (post-checkout projects use a different dockerfile).
# 4) The container is not running.
host.is_rebuild_necessary() {
  local checked_out_project="$(lib.checked_out_project)"
  local target_project="${1:-"${checked_out_project}"}"
  local target_project_dockerfile="$(host.get_project_dockerfile "${target_project}")"
  if [[ ! -f ${target_project_dockerfile} ]]; then
    target_project_dockerfile="${host__project_fallback_dockerfile}"
  fi
  local built_project="$(cat "${host__data_cli_dir_built_project_file}" 2>/dev/null || echo "")"
  local built_project_from_dockerfile="$(cat "${host__data_cli_dir_built_project_from_dockerfile_file}" 2>/dev/null || echo "")"
  if [[ -z ${built_project} ]]; then
    return 0
  elif [[ -z ${built_project_from_dockerfile} ]]; then
    return 0
  elif [[ ${target_project} != "${built_project}" ]]; then
    return 0
  elif [[ ${target_project_dockerfile} != "${built_project_from_dockerfile}" ]]; then
    return 0
  elif ! docker exec "${host__project_docker_container}" echo "" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}
host.destroy() {
  # Destroy everything.
  local image_names="$(docker ps -a --format '{{.Image}}' | xargs)"
  for image_name in ${image_names}; do
    if [[ ${image_name} = "${host__base_docker_image}" ]] || [[ ${image_name} = "${host__project_docker_image}" ]]; then
      host.log_info "Stopping container(s) running image: ${image_name}"
      if ! docker stop "$(docker ps -a --format '{{.ID}}' --filter ancestor="${image_name}")" >/dev/null; then
        host.log_error "Failed to stop the container with image name ${image_name}."
        return 1
      fi
      host.log_info "Removing container(s) running image: ${image_name}"
      if ! docker rm "$(docker ps -a --format '{{.ID}}' --filter ancestor="${image_name}")" >/dev/null; then
        host.log_error "Failed to remove the container with image name ${image_name}."
        return 1
      fi
      host.log_info "Removing image: ${image_name}"
      if ! docker rmi "${image_name}" >/dev/null; then
        host.log_error "Failed to remove the image with image name ${image_name}."
        return 1
      fi
    fi
  done
}
# Steps:
# - destroy existing containers and images.
# - determine which dockerfile to use for the project (the custom one or the default one).
# - ensure the dockerfile for the project extends the solos:latest base image.
# - build the base image.
# - build the project image.
# - save the project name and dockerfile path used to build the container to a file.
# - save the user's home directory to a file.
# - start the project container.
# - wait for the container to be ready.
host.build() {
  # `target_project` is the project that we want to build a container for.
  # `target_project` does not need to be checked out in order for us to build it.
  # Once the checkout happens, other logic will determine if a rebuild is necessary.
  local target_project="${1}"
  shift
  if ! host.destroy; then
    host.log_error "Failed to destroy existing containers and images."
    return 1
  fi
  # Only projects that were checked out will have a custom Dockerfile.
  local target_project_dockerfile="$(host.get_project_dockerfile "${target_project}")"
  local project_dockerfile=""
  if [[ -f ${target_project_dockerfile} ]]; then
    project_dockerfile="${target_project_dockerfile}"
  else
    project_dockerfile="${host__project_fallback_dockerfile}"
  fi

  # Don't allow the user to build a dockerfile that doesn't extend the solos:latest base image.
  local project_dockerfile_first_line="$(
    cat "${project_dockerfile}" | grep -vE '^\s*#' | grep -vE '^\s*$' | head -n 1 | xargs
  )"
  if [[ ${project_dockerfile_first_line} != 'FROM '"${host__base_docker_image}"'' ]]; then
    host.log_error "User error: SolOS expects the first statement in ${project_dockerfile} to be: \`FROM solos:latest\`."
    return 1
  fi

  # Build the base image, and the project image if a project is checked out.
  if ! docker build "$@" -t "${host__base_docker_image}" -f "${host__base_dockerfile}" . >/dev/null; then
    host.log_error "Failed to build the dockerfile: ${host__base_dockerfile}."
    return 1
  fi
  host.log_info "Built the base docker image - ${host__base_docker_image}"
  if ! docker build "$@" -t "${host__project_docker_image}" -f "${project_dockerfile}" . >/dev/null; then
    host.log_error "Failed to build the dockerfile: ${project_dockerfile}."
    return 1
  fi
  host.log_info "Built the project docker image - ${host__project_docker_image}"

  # Need these values to determine whether or not rebuilds should happen in the future.
  echo "${project_dockerfile}" >"${host__data_cli_dir_built_project_from_dockerfile_file}"
  echo "${target_project}" >"${host__data_cli_dir_built_project_file}"

  # Save the user's home directory for reference inside the container.
  local curr_home_dir="$(cat "${host__data_store_users_home_dir_file}" 2>/dev/null || echo "")"
  if [[ ${HOME} != "${curr_home_dir}" ]]; then
    mkdir -p "$(dirname "${host__data_store_users_home_dir_file}")"
    echo "${HOME}" >"${host__data_store_users_home_dir_file}"
    host.log_info "Saved the user's home directory to the store directory."
  fi

  # Start the project container.
  if
    ! docker run \
      -d \
      -p 7000:7000 \
      --name "${host__project_docker_container}" \
      --pid host \
      --privileged \
      --cpus=4 \
      -v "/var/run/docker.sock:/var/run/docker.sock" \
      -v "${HOME}/.solos:/root/.solos" \
      "${host__project_docker_image}" tail -f /dev/null >/dev/null
  then
    host.log_error "Failed to run the docker container."
    return 1
  fi

  # Wait for the container to be ready by checking if we can execute an echo command inside it.
  host.log_info "Started the \`"${host__project_docker_container}"\` container using image: ${host__project_docker_image}"
  while ! docker exec "${host__project_docker_container}" echo "" >/dev/null 2>&1; do
    sleep .2
  done
  host.log_info "The development container is ready."
}
# This will ensure the project name supplied is valid and that if an empty name is supplied,
# it will default to the previously checked out project. And if no project has been checked out,
# it will default the project name to "NONE". "NONE" could just be an empty string, but the word "NONE"
# makes the downstream code more explicit about the fact that no project was specified or checked out.
host.acquire_target_project() {
  local checked_out_project="$(lib.checked_out_project)"
  local target_project="${1:-"${checked_out_project}"}"
  if [[ ${target_project} = "NONE" ]]; then
    host.log_error "The project name \`NONE\` is reserved in SolOS."
    return 1
  fi
  if [[ -z ${target_project} ]]; then
    target_project="NONE"
  fi
  local solos_cmd_names="bash bash:minimal rebuild rebuild:no-cache dispose vscode"
  for solos_cmd_name in ${solos_cmd_names}; do
    if [[ ${target_project} = "${solos_cmd_name}" ]]; then
      host.log_error "Cannot use the project name \`${target_project}\` as it conflicts with a SolOS command name."
      return 1
    fi
  done
  if [[ ! ${target_project} =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
    host.log_error 'Project name must start with a letter and contain only letters, numbers, and underscores (^[a-zA-Z][a-zA-Z0-9_]*$).'
    return 1
  fi
  echo "${target_project}"
}
# This will perform a rebuild of the container if necessary, and then check out the project.
# If we find that the checked out project stored in our filesystem is the same as the project
# name supplied, we return early with a success code
host.checkout() {
  local target_project="${1}"
  if [[ ${target_project} = "NONE" ]]; then
    host.log_error "You must specify a project name to check out a project."
    return 1
  fi
  local was_rebuilt=false
  if host.is_rebuild_necessary "${target_project}"; then
    if ! host.build "${target_project}"; then
      host.log_error "Failed to rebuild the development container for project: ${target_project}"
      return 1
    fi
    was_rebuilt=true
  fi
  local checked_out_project="$(lib.checked_out_project)"
  if [[ ${checked_out_project} = "${target_project}" ]]; then
    return 0
  fi
  host.log_info "Checking out project: ${target_project}"
  docker exec \
    -it "${host__project_docker_container}" \
    /bin/bash -c '"'"${host__containerized_bin_path}"'" "'"${target_project}"'"'
  if [[ $? -ne 0 ]]; then
    return 1
  fi
  local newly_checked_out_project="$(lib.checked_out_project)"
  if [[ ${newly_checked_out_project} != "${target_project}" ]]; then
    host.log_error "We expected the newly checked out project to equal: ${target_project} but got ${newly_checked_out_project} instead."
    return 1
  elif host.is_rebuild_necessary "${target_project}"; then
    if ! host.build "${target_project}"; then
      host.log_error "Failed to rebuild the development container for project: ${target_project}"
      return 1
    fi
  fi
  host.log_success "Checked out project: ${target_project}"
}

## ENTRY FUNCTIONS

host.entry_rebuild() {
  local target_project="${1}"
  if ! host.build "${target_project}"; then
    host.log_error "Failed to rebuild the development container."
    return 1
  fi
  host.log_success "Rebuilt the development container for project: ${target_project}"
}
host.entry_dispose() {
  if ! host.destroy; then
    host.log_error "Failed to rebuild the development container."
    return 1
  fi
  if ! rm -f "${host__data_cli_dir_built_project_from_dockerfile_file}"; then
    host.log_error "Failed to remove the built project from dockerfile file."
    return 1
  fi
  if ! rm -f "${host__data_cli_dir_built_project_file}"; then
    host.log_error "Failed to remove the built project file."
    return 1
  fi
  host.log_success "The development container was successfully dispose."
}
# This will attempt to checkout the project specified and then start an interactive
# Bash shell within the container. If a custom bashrc file is supplied, it will be used.
# For now, the only custom RC file we use is the one we create for the user that auto
# installs all the SolOS shell commands.
host.entry_shell() {
  local supported_shells="bash"
  local target_project="${1:-""}"
  local target_shell="${2:-"bash"}"
  if [[ -z ${target_shell} ]]; then
    host.log_error "No IDE was specified."
    return 1
  fi
  if [[ ${supported_shells} != *"${target_shell}"* ]]; then
    host.log_error "Unsupported SHELL: ${target_shell}"
    return 1
  fi
  if [[ ${target_project} = "NONE" ]]; then
    host.log_error "You must specify a project name or have a project checked out."
    return 1
  fi
  local bashrc_file="${3:-""}"
  local mounted_volume_dir="${HOME}/.solos"
  local working_dir="${4:-"${mounted_volume_dir}"}"
  local container_ctx="${working_dir/#$HOME//root}"
  if [[ ${container_ctx} != "/root/.solos"* ]]; then
    container_ctx="/root/.solos"
  fi
  if ! host.checkout "${target_project}"; then
    lib.enter_to_exit
  fi
  if [[ -n ${bashrc_file} ]]; then
    if [[ ! -f ${bashrc_file} ]]; then
      host.log_error "The supplied bashrc file at ${bashrc_file} does not exist."
      lib.enter_to_exit
    fi
    local relative_bashrc_file="${bashrc_file/#$HOME/~}"
    if ! docker exec -it -w "${container_ctx}" "${host__project_docker_container}" /bin/bash --rcfile "${relative_bashrc_file}" -i; then
      host.log_error "Failed to start the shell with the supplied bashrc file."
      lib.enter_to_exit
    fi
  elif ! docker exec -it -w "${container_ctx}" "${host__project_docker_container}" /bin/bash -i; then
    host.log_error "Failed to start the shell."
    lib.enter_to_exit
  fi
}
host.entry_ide() {
  local supported_ides="vscode"
  local target_project="${1}"
  local target_ide="${2}"
  # PRECHECKS
  if [[ -z ${target_ide} ]]; then
    host.log_error "No IDE was specified."
    return 1
  fi
  if [[ ${supported_ides} != *"${target_ide}"* ]]; then
    host.log_error "Unsupported IDE: ${target_ide}"
    return 1
  fi
  if [[ ${target_project} = "NONE" ]]; then
    host.log_error "You must specify a project name or have a project checked out."
    return 1
  fi
  # REBUILD BEFORE RUNNING
  if host.is_rebuild_necessary "${target_project}"; then
    if ! host.build "${target_project}"; then
      host.log_error "Failed to rebuild the development container for project: ${target_project}"
      return 1
    fi
  fi
  # RUN THE IDE INTEGRATION
  if ! host.checkout "${target_project}"; then
    return 1
  fi
  local code_workspace_file="$(host.get_project_vscode_workspace_file "${target_project}")"
  if [[ -f ${code_workspace_file} ]]; then
    if command -v code >/dev/null; then
      code "${code_workspace_file}"
    else
      host.log_success "Generated VSCode workspace file: ${code_workspace_file}"
    fi
    return 0
  else
    host.log_error "Failed to find a code-workspace file at: ${code_workspace_file}"
    return 1
  fi
}
# This wraps the bin/container.sh script that we use to checkout projects. The build logic
# allows the use of the "NONE" project name and will fallback to building a default dockerfile.
# This is important so that we can access commands like --help or --noop before running project-specific
# commands.
host.entry_container_bin() {
  local supported_bin_cmds="checkout --help --noop"
  local target_project="${1}"
  local bin_cmd="${2}"
  # PRECHECKS
  if [[ -z ${bin_cmd} ]]; then
    host.log_error "No command was supplied."
    return 1
  fi
  if [[ ${supported_bin_cmds} != *"${bin_cmd}"* ]]; then
    host.log_error "Unsupported command: ${bin_cmd}"
    return 1
  fi
  # REBUILD BEFORE RUNNING
  if host.is_rebuild_necessary "${target_project}"; then
    if ! host.build "${target_project}"; then
      host.log_error "Failed to rebuild the development container for project: ${target_project}"
      return 1
    fi
  fi
  # RUN THE COMMAND
  if [[ ${bin_cmd} = "--help" ]] || [[ ${bin_cmd} = "--noop" ]]; then
    docker exec -it "${host__project_docker_container}" /bin/bash -c '"'"${host__containerized_bin_path}"'" '"${bin_cmd}"''
    if [[ $? -ne 0 ]]; then
      return 1
    fi
    return 0
  fi
  if [[ ${target_project} = "NONE" ]]; then
    host.log_error "You must specify a project name or have a project checked out."
    return 1
  fi
  if [[ ${bin_cmd} = "checkout" ]]; then
    if ! host.checkout "${target_project}"; then
      return 1
    fi
    return 0
  fi
  host.log_error "Internal error - no handling logic for ${bin_cmd}"
  return 1
}

## MAIN FUNCTION

# Maps commands as described in the --help output to functions defined above.
host() {
  local target_project="$(host.acquire_target_project "${2}")"
  if [[ -z ${target_project} ]]; then
    exit 1
  fi
  # Subcommands don't have usage (because they have no options), but a curious developer will still try
  # to run them with --help, so a warning is helpful.
  if [[ ${2} = "help" ]] || [[ ${2} = "--help" ]] || [[ ${2} = "-h" ]]; then
    host.log_warn "\`solos ${1}\` does not support any options. Use \`solos --help\` for usage information."
    exit 1
  elif [[ ${1} = "bash" ]]; then
    host.entry_shell "${target_project}" "bash" "${host__user_bashrc_file}" "${PWD}"
    exit $?
  elif [[ ${1} = "bash:minimal" ]]; then
    host.entry_shell "${target_project}" "bash" "" "${PWD}"
    exit $?
  elif [[ ${1} = "rebuild" ]]; then
    host.entry_rebuild "${target_project}"
    exit $?
  elif [[ ${1} = "rebuild:no-cache" ]]; then
    host.entry_rebuild "${target_project}" --no-cache
    exit $?
  elif [[ ${1} = "dispose" ]]; then
    host.entry_dispose "${target_project}"
    exit $?
  elif [[ ${1} = "vscode" ]]; then
    host.entry_ide "${target_project}" vscode
    exit $?
  elif [[ ${1} = "noop" ]]; then
    host.entry_container_bin "${target_project}" --noop
    exit $?
  elif [[ -z ${1} ]] || [[ ${1} = "help" ]] || [[ ${1} = "--help" ]] || [[ ${1} = "-h" ]]; then
    host.entry_container_bin "${target_project}" --help
    exit $?
  else
    host.log_error "Unknown command supplied: ${1}"
    exit 1
  fi
}

host "$@"
