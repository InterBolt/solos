#!/usr/bin/env bash

# Any variables that might get used in template replacements should be defined here.
container__project=""

container__solos_dir="${HOME}/.solos"
container__repo_dir="${container__solos_dir}/repo"
container__data_dir="${container__solos_dir}/data"
container__projects_dir="${container__solos_dir}/projects"
container__data_store_dir="${container__data_dir}/store"
container__data_cli_dir="${container__data_dir}/cli"
container__project_template_code_workspace_file="${container__repo_dir}/src/bin/project.code-workspace"
container__project_fallback_dockerfile="${container__repo_dir}/src/Dockerfile.project"
container__data_cli_dir_master_log_file="${container__data_cli_dir}/master.log"
container__checked_out_project_store_file="${container__data_store_dir}/checked_out_project"
container__data_store_users_home_dir_file="${container__data_store_dir}/users_home_dir"

# We can't build a valid code-workspace file without knowing the user's home directory.
if [[ ! -f ${container__data_store_users_home_dir_file} ]]; then
  echo "Unexpected error: the user's home directory was not saved to ${container__data_store_users_home_dir_file}." >&2
  exit 1
fi
container__users_home_dir="$(cat "${container__data_store_users_home_dir_file}" || echo "")"

# For simplicity, let's ensure we're in the base directory of our SolOS installation.
# It's possible that this won't/doesn't matter, but it's a nice assurance to have as changes are made.
cd "${container__solos_dir}"

# Logging stuff.
. "${container__repo_dir}/src/shared/log.universal.sh" || exit 1
log.use "${container__data_cli_dir_master_log_file}"
container.log_info() {
  log.info "(CLI:CONTAINER) ${1}"
}
container.log_success() {
  log.info "(CLI:CONTAINER) ${1}"
}
container.log_warn() {
  log.warn "(CLI:CONTAINER) ${1}"
}
container.log_error() {
  log.error "(CLI:CONTAINER) ${1}"
}

# Help/usage stuff.
container.help() {
  cat <<EOF
USAGE: solos COMMAND [PROJECT_NAME]

DESCRIPTION:

The SolOS CLI for MacOS - manage development containers for various projects.

A project is not meant to be a single codebase or repo, but rather a collection of related works. \
For example, a consultant might have a single project per each client, but each client's "project" \
might contain several repos, apps, scripts, etc.

COMMANDS:

- bash              Connect to a fully featured SolOS Bash session running in the development container.
- bash:minimal      Connect to a Bash session running in the development container.
- vscode            Launches a VSCode workspace.
- rebuild           Rebuilds the development container.
- rebuild:no-cache  Rebuilds the development container using Docker's --no-cache option.
- dispose           Stops and destroys the development container.

EOF
}
if [[ ${1} = "--help" ]] || [[ ${1} = "-h" ]] || [[ ${1} = "help" ]]; then
  container.help
  exit 0
fi
if [[ ${1} = "--noop" ]]; then
  exit 0
fi

# Grab the project name from either the first argument, or the checked out project store file.
# This allows users to simply type: "solos" without having to remember the project name.
if [[ -n ${1} ]]; then
  container__project="${1}"
  shift
elif [[ -f ${container__checked_out_project_store_file} ]]; then
  container__project="$(cat "${container__checked_out_project_store_file}" || echo "")"
  if [[ -z ${container__project} ]]; then
    container.log_error "No project checked out."
    exit 1
  fi
else
  container.log_warn "No project checked out."
  container.help
  exit 1
fi

# Allows us to replace template string variables in files where the
# template string is in the format ___container__variable_name___ and container__variable_name
# is a variable defined here in this script.
container.do_template_variable_replacements() {
  local dir_or_file="$1"
  local eligible_files=()
  if [[ -d ${dir_or_file} ]]; then
    for file in "${dir_or_file}"/*; do
      if [[ -d ${file} ]]; then
        container.do_template_variable_replacements "${file}"
      fi
      if [[ -f ${file} ]]; then
        eligible_files+=("${file}")
      fi
    done
  elif [[ -f ${dir_or_file} ]]; then
    eligible_files+=("${dir_or_file}")
  fi
  if [[ ${#eligible_files[@]} -eq 0 ]]; then
    return
  fi
  local errored=false
  for file in "${eligible_files[@]}"; do
    local bin_vars=($(grep -o "___container__[a-z0-9_]*___" "${file}" | sed 's/___//g' | xargs))
    for bin_var in "${bin_vars[@]}"; do
      if [[ -z ${!bin_var+x} ]]; then
        container.log_error "Template variables error: ${file} is using an unset variable: ${bin_var}"
        errored=true
        continue
      fi
      if [[ -z ${!bin_var} ]]; then
        container.log_error "Template variables error: ${file} is using an empty variable: ${bin_var}"
        errored=true
        continue
      fi
      if [[ ${errored} = "false" ]]; then
        sed -i "s,___${bin_var}___,${!bin_var},g" "${file}"
      fi
    done
  done
  if [[ ${errored} = "true" ]]; then
    exit 1
  fi
}
container() {
  if [[ -z ${container__project} ]]; then
    container.log_error "No project name was supplied."
    exit 1
  fi

  # Create the projects directory if it doesn't exist.
  if [[ ! -d ${container__projects_dir} ]]; then
    mkdir -p "${container__projects_dir}"
    container.log_info "No projects found. Creating ${container__projects_dir} directory."
  fi

  # Create the project directory if it doesn't exist.
  local project_dir="${container__projects_dir}/${container__project}"
  if [[ ! -d ${project_dir} ]]; then
    mkdir -p "${project_dir}"
    container.log_info "${container__project} - Created ${project_dir}"
  fi

  # Initialize the ignore file for plugins if it doesn't exist.
  local ignore_file="${project_dir}/.solosignore.plugins"
  if [[ ! -f ${ignore_file} ]]; then
    echo "# Any plugin names listed below this line will be turned off when working in this project." \
      >"${ignore_file}"
    container.log_info "${container__project} - Created ${ignore_file}."
  fi

  # Create the vscode directory if it doesn't exist.
  local vscode_dir="${project_dir}/.vscode"
  if [[ ! -d ${vscode_dir} ]]; then
    mkdir -p "${vscode_dir}"
    container.log_info "${container__project} - Created ${vscode_dir}"
  fi

  # Create the code-workspace file if it doesn't exist.
  local code_workspace_file="${vscode_dir}/${container__project}.code-workspace"
  if [[ ! -f ${code_workspace_file} ]]; then
    local template_code_workspace_file="${container__project_template_code_workspace_file}"
    local tmp_dir="$(mktemp -d -q)"
    local tmp_code_workspace_file="${tmp_dir}/${container__project}.code-workspace"
    if ! cp "${template_code_workspace_file}" "${tmp_code_workspace_file}"; then
      container.log_error "${container__project} - Failed to copy the template code workspace file."
      exit 1
    fi
    if container.do_template_variable_replacements "${tmp_code_workspace_file}"; then
      cp -f "${tmp_code_workspace_file}" "${code_workspace_file}"
      container.log_info "${container__project} - Created ${code_workspace_file} based on template at ${template_code_workspace_file}."
    else
      container.log_error "${container__project} - Failed to build the code workspace file."
      exit 1
    fi
  fi

  # Create an empty checkout script if one doesn't exist.
  local checkout_script="${project_dir}/solos.checkout.sh"
  if [[ -f ${checkout_script} ]]; then
    chmod +x "${checkout_script}"
    if ! "${checkout_script}"; then
      container.log_warn "${container__project} - Failed to run the checkout script."
    else
      container.log_info "${container__project} - Checkout out."
    fi
  else
    cat <<EOF >"${checkout_script}"
#!/usr/bin/env bash

echo "Hello from the checkout script for project: ${container__project}"

EOF
    chmod +x "${checkout_script}"
    container.log_info "${container__project} - initialized the checkout script."
  fi

  # Make sure the store directory exists.
  if [[ ! -d ${container__data_store_dir} ]]; then
    mkdir -p "${container__data_store_dir}"
    container.log_info "${container__project} - created ${container__data_store_dir}"
  fi

  local project_dockerfile="${project_dir}/Dockerfile"
  if [[ ! -f ${project_dockerfile} ]]; then
    cp "${container__project_fallback_dockerfile}" "${project_dockerfile}"
    container.log_info "${container__project} - copied ${container__project_fallback_dockerfile} to ${project_dockerfile}"
  fi

  # Save the project name so we can re-use it later.
  if [[ ! -f ${container__checked_out_project_store_file} ]]; then
    touch "${container__checked_out_project_store_file}"
    container.log_info "${container__project} - touched ${container__checked_out_project_store_file}"
  fi
  echo "${container__project}" >"${container__checked_out_project_store_file}"
  container.log_info "${container__project} - ready."
}

# Run the script, but error if any arguments are supplied that shouldn't be there.
if [[ $# -ne 0 ]]; then
  container.log_error "Unexpected error: arguments not supported: [${*}]"
  exit 1
fi

container
