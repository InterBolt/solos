#!/usr/bin/env bash

. "${HOME}/.solos/repo/src/shared/lib.universal.sh" || exit 1
. "${HOME}/.solos/repo/src/shared/log.universal.sh" || exit 1

daemon__verbose=false
daemon__pid=$$
daemon__max_retries=5
daemon__remaining_retries="${daemon__max_retries}"
daemon__solos_dir="${HOME}/.solos"
daemon__scrubbed_dir=""
daemon__cli_data_dir="${daemon__solos_dir}/data/cli"
daemon__daemon_data_dir="${daemon__solos_dir}/data/daemon"
daemon__user_plugins_dir="${daemon__solos_dir}/plugins"
daemon__manifest_file="${daemon__user_plugins_dir}/solos.manifest.json"
daemon__solos_plugins_dir="${daemon__solos_dir}/repo/src/daemon/plugins"
daemon__panics_dir="${daemon__solos_dir}/data/panics"
daemon__precheck_plugin_path="${daemon__solos_plugins_dir}/precheck"
daemon__users_home_dir="$(lib.home_dir_path)"
daemon__pid_file="${daemon__daemon_data_dir}/pid"
daemon__status_file="${daemon__daemon_data_dir}/status"
daemon__last_active_at_file="${daemon__daemon_data_dir}/last_active_at"
daemon__request_file="${daemon__daemon_data_dir}/request"
daemon__running_checked_out_project_file="${daemon__daemon_data_dir}/running_checked_out_project"
daemon__frozen_manifest_file="${daemon__daemon_data_dir}/frozen.manifest.json"
daemon__log_file="${daemon__daemon_data_dir}/master.log"
daemon__prev_pid="$(cat "${daemon__pid_file}" 2>/dev/null || echo "" | head -n 1 | xargs)"
daemon__precheck_plugin_names=("precheck")
daemon__checked_out_project="$(lib.checked_out_project)"
daemon__checked_out_project_path="/root/.solos/projects/${daemon__checked_out_project}"
daemon__tmp_data_dir="${daemon__daemon_data_dir}/tmp"
daemon__blacklisted_exts=(
  "pem"
  "key"
  "cer"
  "crt"
  "der"
  "pfx"
  "p12"
  "p7b"
  "p7c"
  "p7a"
  "p8"
  "spc"
  "rsa"
  "jwk"
  "pri"
  "bin"
  "asc"
  "gpg"
  "pgp"
  "kdb"
  "kdbx"
  "ovpn"
  "enc"
  "jks"
  "keystore"
  "ssh"
  "ppk"
  "xml"
  "bak"
  "zip"
  "tar"
  "gz"
  "tgz"
  "rar"
  "java"
  "rtf"
  "xlsx"
  "pptx"
)

mkdir -p "${daemon__daemon_data_dir}"
trap 'trap - SIGTERM && daemon.cleanup;' SIGTERM EXIT

log.use "${daemon__log_file}"
daemon.log_info() {
  log.info "(DAEMON) ${1} pid=${daemon__pid}"
}
daemon.log_error() {
  log.error "(DAEMON) ${1} pid=${daemon__pid}"
}
daemon.log_warn() {
  log.warn "(DAEMON) ${1} pid=${daemon__pid}"
}
daemon.log_verbose() {
  if [[ ${daemon__verbose} = true ]]; then
    log.info "(DAEMON) ${1} pid=${daemon__pid}"
  fi
}

daemon.cleanup() {
  if daemon.fs_unbind_all; then
    rm -rf "${daemon__tmp_data_dir}"
    daemon.log_info "Cleaned up the temporary data directory: ${daemon__tmp_data_dir}"
  else
    daemon.log_error "Failed to unbind all files and directories."
  fi
  if [[ -f ${daemon__pid_file} ]]; then
    rm -f "${daemon__pid_file}"
    daemon.log_info "Removed the daemon pid file: ${daemon__pid_file}"
  fi
  daemon.status "DOWN"
  kill -9 "${daemon__pid}"
}
daemon.parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
    --verbose)
      daemon__verbose=true
      shift
      ;;
    *)
      log.error "Unknown argument: $1"
      exit 1
      ;;
    esac
  done
}
daemon.get_host_path() {
  local path="${1}"
  echo "${path/\/root\//${daemon__users_home_dir}\/}"
}
daemon.exit_listener() {
  while true; do
    local seconds_timestamp="$(date +%s)"
    echo "${daemon__checked_out_project} ${seconds_timestamp}" >"${daemon__last_active_at_file}"
    # This would indicate a pretty serious logic bug if the project doesn't exist in the filesystem.
    # Best to get the fuck out of here when that happens.
    if [[ ! -d ${daemon__checked_out_project_path} ]]; then
      daemon.log_error "The checked out project is no longer present in the filesystem at: ${daemon__checked_out_project_path}."
      kill -SIGTERM "${daemon__pid}"
      return 1
    fi
    # If the checked out project has changed, exit.
    if [[ ${daemon__checked_out_project} != "$(lib.checked_out_project)" ]]; then
      daemon.log_error "The checked out project has changed."
      kill -SIGTERM "${daemon__pid}"
      return 1
    fi
    # Handle requests from the user.
    if [[ -f ${daemon__request_file} ]]; then
      requested_action="$(cat "${daemon__request_file}" 2>/dev/null || echo "" | head -n 1 | xargs)"
    fi
    if [[ -n ${requested_action} ]]; then
      rm -f "${daemon__request_file}"
      case "${requested_action}" in
      "KILL")
        daemon.log_error "A KILL request was received."
        kill -SIGTERM "${daemon__pid}"
        return 1
        ;;
      *)
        daemon.log_error "Unknown user request ${request}"
        ;;
      esac
    fi
    sleep 2
  done
}
declare -A fs_bind_store=()
daemon.fs_unbind() {
  local dest="${1}"
  if [[ -z ${fs_bind_store["${dest}"]} ]]; then
    daemon.log_error "No bind source was found for: ${dest}"
    return 1
  fi
  local src="${fs_bind_store["${dest}"]}"
  if [[ -f ${src} ]]; then
    if ! rm -f "${dest}"; then
      daemon.log_error "Failed to remove the hard link: ${src} -> ${dest}"
      return 1
    fi
    daemon.log_verbose "Unlinked: ${src} =/=> ${dest}"
  elif ! umount "${dest}"; then
    daemon.log_error "Failed to unmount the bind mount: ${src} -> ${dest}"
    return 1
  else
    daemon.log_verbose "Umounted ${src} =/=> ${dest}"
  fi
  if ! unset fs_bind_store["${dest}"]; then
    daemon.log_error "Failed to unset the bind source for: ${dest}. This could result in a memory leak or dangling bind mounts and/or hard links."
    return 1
  fi
  daemon.log_verbose "Unset bind store destination: ${dest}"
}
daemon.fs_unbind_all() {
  for dest in "${!fs_bind_store[@]}"; do
    if ! daemon.fs_unbind "${dest}"; then
      return 1
    fi
  done
  local dangling_bind_mounts=($(findmnt -r | grep "${daemon__tmp_data_dir}" | cut -d' ' -f1 | xargs))
  if [[ -n ${dangling_bind_mounts[*]} ]]; then
    if ! umount "${dangling_bind_mounts[@]}"; then
      daemon.log_error "Failed to umount ${#dangling_bind_mounts} dangling bind mounts."
      return 1
    fi
    daemon.log_info "Umounted ${#dangling_bind_mounts} bind mounts within: ${daemon__tmp_data_dir}."
    for dangling_bind_mount in "${dangling_bind_mounts[@]}"; do
      daemon.log_verbose "Removed bind mount: ${dangling_bind_mount}"
    done
  else
    daemon.log_verbose "No dangling bind mounts found in ${daemon__tmp_data_dir}."
  fi
}
daemon.fs_bind() {
  local src="${1}"
  local dest="${2}"
  if [[ ${dest} != "${daemon__tmp_data_dir}/"* ]]; then
    daemon.log_error "Cannot bind mount outside of ${daemon__tmp_data_dir}."
    return 1
  fi
  if [[ -f ${src} ]]; then
    if ! ln "${src}" "${dest}"; then
      daemon.log_error "Failed to hard link ${src} to ${dest}."
      return 1
    fi
    daemon.log_verbose "Hard link: ${src} -> ${dest}"
  elif ! mount -o bind "${src}" "${dest}"; then
    daemon.log_error "Failed to bind mount ${src} to ${dest}."
    return 1
  else
    daemon.log_verbose "Bind mount: ${src} -> ${dest}"
  fi
  fs_bind_store["${dest}"]="${src}"
  daemon.log_verbose "Saved binding in memory: ${src} -> ${dest}"
}
daemon.fs_bind_source() {
  local dest="${1}"
  echo "${fs_bind_store["${dest}"]}"
}
daemon.mktemp_dir() {
  mkdir -p "${daemon__tmp_data_dir}"
  local random_unique_name="$(date +%N | sha256sum | base64 | head -c 12)"
  local tmp_dir="${daemon__tmp_data_dir}/${random_unique_name}"
  if ! mkdir -p "${tmp_dir}"; then
    daemon.log_error "Failed to create temporary directory: ${tmp_dir}"
    return 1
  fi
  daemon.log_verbose "Created temporary directory: ${tmp_dir}"
  echo "${tmp_dir}"
}
daemon.mktemp_file() {
  mkdir -p "${daemon__tmp_data_dir}"
  local random_unique_name="$(date +%N | sha256sum | base64 | head -c 12)"
  local tmp_file="${daemon__tmp_data_dir}/${random_unique_name}"
  if ! touch "${tmp_file}"; then
    daemon.log_error "Failed to create temporary file: ${tmp_file}"
    return 1
  fi
  daemon.log_verbose "Created temporary file: ${tmp_file}"
  echo "${tmp_file}"
}
daemon.get_solos_plugin_names() {
  local solos_plugin_names=()
  local plugins_dirbasename="$(basename "${daemon__solos_plugins_dir}")"
  for solos_plugin_path in "${daemon__solos_plugins_dir}"/*; do
    if [[ ${solos_plugin_path} = "${plugins_dirbasename}" ]]; then
      continue
    fi
    if [[ -d ${solos_plugin_path} ]]; then
      solos_plugin_names+=("solos-$(basename "${solos_plugin_path}")")
    fi
  done
  echo "${solos_plugin_names[@]}" | xargs
}
daemon.get_user_plugin_names() {
  local user_plugin_names=()
  local plugins_dirbasename="$(basename "${daemon__user_plugins_dir}")"
  for user_plugin_path in "${daemon__user_plugins_dir}"/*; do
    if [[ ${user_plugin_path} = "${plugins_dirbasename}" ]]; then
      continue
    fi
    if [[ -d ${user_plugin_path} ]]; then
      user_plugin_names+=("user-$(basename "${user_plugin_path}")")
    fi
  done
  echo "${user_plugin_names[@]}" | xargs
}
daemon.plugin_paths_to_names() {
  local plugins=($(echo "${1}" | xargs))
  local plugin_names=()
  for plugin in "${plugins[@]}"; do
    if [[ ${plugin} = "${daemon__precheck_plugin_path}" ]]; then
      plugin_names+=("${daemon__precheck_plugin_names[@]}")
    elif [[ ${plugin} =~ ^"${daemon__user_plugins_dir}" ]]; then
      plugin_names+=("user-$(basename "${plugin}")")
    else
      plugin_names+=("solos-$(basename "${plugin}")")
    fi
  done
  echo "${plugin_names[*]}" | xargs
}
daemon.plugin_names_to_paths() {
  local plugin_names=($(echo "${1}" | xargs))
  local plugins=()
  for plugin_name in "${plugin_names[@]}"; do
    if [[ ${plugin_name} = "precheck" ]]; then
      plugins+=("${daemon__precheck_plugin_path}")
    elif [[ ${plugin_name} =~ ^solos- ]]; then
      plugin_name="${plugin_name#solos-}"
      plugins+=("${daemon__solos_plugins_dir}/${plugin_name}")
    elif [[ ${plugin_name} =~ ^user- ]]; then
      plugin_name="${plugin_name#user-}"
      plugins+=("${daemon__user_plugins_dir}/${plugin_name}")
    fi
  done
  echo "${plugins[*]}" | xargs
}
daemon.status() {
  local status="$1"
  local previous_status="$(cat "${daemon__status_file}" 2>/dev/null || echo "" | head -n 1 | xargs)"
  if [[ ${previous_status} = ${status} ]]; then
    return 0
  fi
  echo "${status}" >"${daemon__status_file}"
  daemon.log_info "Update status from ${previous_status} to ${status}"
}
daemon.project_found() {
  if [[ -z ${daemon__checked_out_project} ]]; then
    daemon.log_error "No project is checked out."
    return 1
  fi
  if [[ ! -d ${daemon__checked_out_project_path} ]]; then
    daemon.log_error "${daemon__checked_out_project_path} does not exist."
    return 1
  fi
}
daemon.create_scrub_copy() {
  local cp_tmp_dir="$(daemon.mktemp_dir)"
  if ! rm -rf "${daemon__tmp_data_dir}"; then
    daemon.log_error "Failed to remove ${daemon__tmp_data_dir}."
    return 1
  fi
  mkdir -p "${daemon__tmp_data_dir}"
  if [[ -z ${daemon__tmp_data_dir} ]]; then
    daemon.log_error "${daemon__tmp_data_dir} does not exist."
    return 1
  fi
  daemon.log_verbose "Initialized fresh temporary directory: ${daemon__tmp_data_dir}"
  if ! mkdir -p "${cp_tmp_dir}/projects/${daemon__checked_out_project}"; then
    daemon.log_error "Failed to create the projects directory in the temporary directory."
    return 1
  fi
  daemon.log_verbose "Initialized ${cp_tmp_dir}/projects/${daemon__checked_out_project}"
  if ! cp -rfa "${daemon__checked_out_project_path}/." "${cp_tmp_dir}/projects/${daemon__checked_out_project}"; then
    daemon.log_error "Failed to copy the project directory: ${daemon__checked_out_project_path} to: ${daemon__tmp_data_dir}/projects/${daemon__checked_out_project}"
    return 1
  fi
  daemon.log_verbose "Copied ${daemon__checked_out_project_path} to ${cp_tmp_dir}/projects/${daemon__checked_out_project}"
  daemon.log_verbose "About to rsync the mounted .solos volume (without extraneous directories) to: ${cp_tmp_dir}"
  rsync \
    -aq \
    --exclude='data/daemon/archives' \
    --exclude='data/daemon/cache' \
    --exclude='data/daemon/tmp' \
    --exclude='data/store' \
    --exclude='plugins' \
    --exclude='projects' \
    /root/.solos/ \
    "${cp_tmp_dir}"/
  local rysnc_exit_code=$?
  # 24 = Partial transfer due to vanished source files
  # This is something we can't rule out and is not fatal. We can ignore it.
  if [[ ${rysnc_exit_code} -ne 0 ]] && [[ ${rysnc_exit_code} -ne 24 ]]; then
    daemon.log_error "Failed to copy the daemon data directory: /root/.solos to: ${cp_tmp_dir}"
    return 1
  fi
  daemon.log_verbose "Rsynced the mounted .solos volume to: ${cp_tmp_dir}"
  local random_dirname="$(date +%s | sha256sum | base64 | head -c 32)"
  mv "${cp_tmp_dir}" "${daemon__tmp_data_dir}/${random_dirname}"
  daemon.log_verbose "Committing the partial mounted .solos volume copy to the temp directory: ${daemon__tmp_data_dir}/${random_dirname}"
  echo "${daemon__tmp_data_dir}/${random_dirname}"
}
daemon.scrub_ssh() {
  local tmp_dir="${1}"
  local ssh_dirpaths=($(find "${tmp_dir}" -type d -name ".ssh" -o -name "ssh" | xargs))
  for ssh_dirpath in "${ssh_dirpaths[@]}"; do
    if ! rm -rf "${ssh_dirpath}"; then
      daemon.log_error "Failed to remove the SSH directory: ${ssh_dirpath} from the temporary directory."
      return 1
    fi
    daemon.log_verbose "Removed potential SSH directory: ${ssh_dirpath}"
  done
}
daemon.scrub_blacklisted_files() {
  local tmp_dir="${1}"
  local find_args=()
  for suspect_extension in "${daemon__blacklisted_exts[@]}"; do
    if [[ ${#find_args[@]} -eq 0 ]]; then
      find_args+=("-name" "*.${suspect_extension}")
      continue
    fi
    find_args+=("-o" "-name" "*.${suspect_extension}")
  done
  local secret_filepaths=($(find "${tmp_dir}" -type f "${find_args[@]}" | xargs))
  for secret_filepath in "${secret_filepaths[@]}"; do
    if ! rm -f "${secret_filepath}"; then
      daemon.log_error "Failed to remove the suspect secret file: ${secret_filepath} from the temporary directory."
      return 1
    fi
    daemon.log_verbose "Removed potentially sensitive file: ${secret_filepath}"
  done
}
daemon.scrub_gitignored() {
  local tmp_dir="${1}"
  local git_dirs=($(find "${tmp_dir}" -type d -name ".git" | xargs))
  for git_dir in "${git_dirs[@]}"; do
    local git_project_path="$(dirname "${git_dir}")"
    local gitignore_path="${git_project_path}/.gitignore"
    if [[ ! -f "${gitignore_path}" ]]; then
      daemon.log_warn "No .gitignore file found in git repo: ${git_project_path}"
      continue
    fi
    local gitignored_paths_to_delete=($(git -C "${git_project_path}" status -s --ignored | grep "^\!\!" | cut -d' ' -f2 | xargs))
    for gitignored_path_to_delete in "${gitignored_paths_to_delete[@]}"; do
      gitignored_path_to_delete="${git_project_path}/${gitignored_path_to_delete}"
      if ! rm -rf "${gitignored_path_to_delete}"; then
        daemon.log_error "${gitignored_path_to_delete} from the temporary directory."
        return 1
      fi
      daemon.log_verbose "Removed gitignored path: ${gitignored_path_to_delete}"
    done
  done
}
daemon.scrub_secrets() {
  local tmp_dir="${1}"
  local tmp_global_secrets_dir="${tmp_dir}/secrets"
  local secrets=()
  # Extract global secrets.
  local global_secret_filepaths=($(find "${tmp_global_secrets_dir}" -maxdepth 1 | xargs))
  local i=0
  for global_secret_filepath in "${global_secret_filepaths[@]}"; do
    if [[ -d ${global_secret_filepath} ]]; then
      continue
    fi
    secrets+=("$(cat "${global_secret_filepath}" 2>/dev/null || echo "" | head -n 1)")
    i=$((i + 1))
  done
  daemon.log_verbose "Extracted ${i} secrets in global secret dir: ${tmp_global_secrets_dir}"
  # Extract project secrets.
  local project_paths=($(find "${tmp_dir}"/projects -maxdepth 1 | xargs))
  for project_path in "${project_paths[@]}"; do
    local tmp_project_secrets_dir="${project_path}/secrets"
    local project_secrets_path="${tmp_project_secrets_dir}"
    if [[ ! -d ${project_secrets_path} ]]; then
      continue
    fi
    local project_secret_filepaths=($(find "${project_secrets_path}" -maxdepth 1 | xargs))
    local i=0
    for project_secret_filepath in "${project_secret_filepaths[@]}"; do
      if [[ -d ${project_secret_filepath} ]]; then
        continue
      fi
      secrets+=("$(cat "${project_secret_filepath}" 2>/dev/null || echo "" | head -n 1)")
      i=$((i + 1))
    done
    daemon.log_verbose "Extracted ${i} secrets in project secret dir: ${tmp_project_secrets_dir}"
  done
  # Extract .env secrets.
  local env_filepaths=($(find "${tmp_dir}" -type f -name ".env"* -o -name ".env" | xargs))
  for env_filepath in "${env_filepaths[@]}"; do
    local env_secrets=($(cat "${env_filepath}" | grep -v '^#' | grep -v '^$' | sed 's/^[^=]*=//g' | sed 's/"//g' | sed "s/'//g" | xargs))
    local i=0
    for env_secret in "${env_secrets[@]}"; do
      secrets+=("${env_secret}")
      i=$((i + 1))
    done
    daemon.log_verbose "Extracted ${i} secrets from env file: ${env_filepath}"
  done
  # Remove duplicates.
  secrets=($(printf "%s\n" "${secrets[@]}" | sort -u))
  # Scrub.
  for secret in "${secrets[@]}"; do
    input_files=$(grep -rl "${secret}" "${tmp_dir}")
    if [[ -z ${input_files} ]]; then
      continue
    fi
    local i=0
    while IFS= read -r input_file; do
      if ! sed -E -i "s@${secret}@[REDACTED]@g" "${input_file}"; then
        daemon.log_error "Failed to scrub ${secret} from ${input_file}."
        return 1
      fi
      i=$((i + 1))
    done <<<"${input_files}"
    daemon.log_verbose "Scrubbed secret: ${secret} from ${i} files."
  done
}
daemon.scrub() {
  if ! daemon.project_found; then
    return 1
  fi
  local tmp_dir="$(daemon.create_scrub_copy)"
  if [[ ! -d ${tmp_dir} ]]; then
    return 1
  fi
  daemon.log_info "Created a copy of the mounted .solos volume for scrubbing: ${tmp_dir}"
  if ! daemon.scrub_gitignored "${tmp_dir}"; then
    return 1
  fi
  daemon.log_verbose "Pruned gitignored files."
  if ! daemon.scrub_ssh "${tmp_dir}"; then
    return 1
  fi
  daemon.log_verbose "Pruned SSH directories."
  if ! daemon.scrub_blacklisted_files "${tmp_dir}"; then
    return 1
  fi
  daemon.log_verbose "Pruned potentially sensitive files based on an extension blacklist."
  if ! daemon.scrub_secrets "${tmp_dir}"; then
    return 1
  fi
  daemon.log_verbose "Scrubbed secrets found in dedicated secrets directories and env files."
  echo "${tmp_dir}"
}
daemon.pid() {
  if [[ -n ${daemon__prev_pid} ]] && [[ ${daemon__prev_pid} -ne ${daemon__pid} ]]; then
    if ps -p "${daemon__prev_pid}" >/dev/null; then
      daemon.log_error "Aborting launch due to existing daemon process with pid: ${daemon__prev_pid}"
      return 1
    fi
  fi
  echo "${daemon__pid}" >"${daemon__pid_file}"
}
daemon.stash_plugin_logs() {
  local phase="${1}"
  local log_file="${2}"
  local aggregated_stdout_file="${3}"
  local aggregated_stderr_file="${4}"
  echo "[${phase} phase:stdout]" >>"${log_file}"
  while IFS= read -r line; do
    echo "${line}" >>"${log_file}"
    daemon.log_verbose "${line}"
  done <"${aggregated_stdout_file}"
  echo "[${phase} phase:stderr]" >>"${log_file}"
  while IFS= read -r line; do
    echo "${line}" >>"${log_file}"
    daemon.log_error "${line}"
  done <"${aggregated_stderr_file}"
  daemon.log_verbose "Stashed plugin logs for ${phase} phase at: ${log_file}"
}
daemon.validate_manifest() {
  local plugins_dir="${1}"
  local manifest_file="${plugins_dir}/solos.manifest.json"
  if [[ ! -f ${manifest_file} ]]; then
    daemon.log_error "No manifest file found at ${manifest_file}"
    return 1
  fi
  local manifest="$(cat ${manifest_file})"
  if [[ ! $(jq '.' <<<"${manifest}") ]]; then
    daemon.log_error "The manifest at ${manifest_file} is not valid JSON."
    return 1
  fi
  local missing_plugins=()
  local changed_plugins=()
  local plugin_names=($(jq -r '.[].name' <<<"${manifest}" | xargs))
  local plugin_sources=($(jq -r '.[].source' <<<"${manifest}" | xargs))
  local i=0
  for plugin_name in "${plugin_names[@]}"; do
    local plugin_path="${plugins_dir}/${plugin_name}"
    local plugin_executable_path="${plugin_path}/plugin"
    local plugin_config_path="${plugin_path}/solos.config.json"
    local plugin_source="${plugin_sources[${i}]}"
    if [[ ! -d ${plugin_path} ]]; then
      missing_plugins+=("${plugin_name}" "${plugin_source}")
      i=$((i + 1))
      continue
    fi
    if [[ ! -f ${plugin_executable_path} ]]; then
      daemon.log_warn "No executable at ${plugin_executable_path}. Will handle this like a missing plugin."
      missing_plugins+=("${plugin_name}" "${plugin_source}")
      i=$((i + 1))
      continue
    fi
    local plugin_config_source="$(jq -r '.source' ${plugin_config_path})"
    if [[ ${plugin_config_source} != "${plugin_source}" ]]; then
      changed_plugins+=("${plugin_name}" "${plugin_source}")
    fi
    i=$((i + 1))
  done
  echo "${missing_plugins[*]}" | xargs
  echo "${changed_plugins[*]}" | xargs
}
daemon.create_empty_plugin_config() {
  local source="${1}"
  local path="${2}"
  cat <<EOF >"${path}"
{
  "source": "${source}",
  "config": {}
}
EOF
}
daemon.curl_plugin() {
  local plugin_source="${1}"
  local output_path="${2}"
  if ! curl -s -o "${output_path}" "${plugin_source}"; then
    daemon.log_error "Curl unable to download ${plugin_source}"
    return 1
  fi
  daemon.log_verbose "Curled ${plugin_source} and downloaded to output path: ${output_path}"
  if ! chmod +x "${output_path}"; then
    daemon.log_error "Unable to make ${output_path} executable."
    return 1
  fi
  daemon.log_verbose "Made ${output_path} executable."
}
daemon.move_plugins() {
  local plugins_dir="${1}"
  local dirs=($(echo "${2}" | xargs))
  local plugin_names=($(echo "${3}" | xargs))
  local i=0
  for dir in "${dirs[@]}"; do
    local plugin_name="${plugin_names[${i}]}"
    local plugin_path="${plugins_dir}/${plugin_name}"
    plugin_paths+=("${plugin_path}")
    if [[ -d ${plugin_path} ]]; then
      if [[ ! -f ${dir}/plugin ]]; then
        daemon.log_error "No plugin executable found at ${dir}/plugin"
        return 1
      fi
      if ! rm -f "${plugin_path}/plugin"; then
        daemon.log_error "Unable to remove old executable at: ${plugin_path}/plugin"
        return 1
      fi
      daemon.log_verbose "Removed ${plugin_path}/plugin"
      if ! rm -f "${plugin_path}/solos.config.json"; then
        daemon.log_error "Unable to remove old executable at: ${plugin_path}/plugin"
        return 1
      fi
      daemon.log_verbose "Removed ${plugin_path}/solos.config.json"
      mv "${dir}/plugin" "${plugin_path}/plugin"
      daemon.log_verbose "Moved ${dir}/plugin to ${plugin_path}/plugin"
      mv "${dir}/solos.config.json" "${plugin_path}/solos.config.json"
      daemon.log_verbose "Moved ${dir}/solos.config.json to ${plugin_path}/solos.config.json"
      i=$((i + 1))
      continue
    fi
    if ! mv "${dir}" "${plugin_path}"; then
      daemon.log_error "Unable to move ${dir} to ${plugin_path}"
      return 1
    fi
    daemon.log_verbose "Moved ${dir} to ${plugin_path}"
    i=$((i + 1))
  done
}
daemon.add_plugins() {
  local plugins_dir="${1}"
  local plugins_and_sources=($(echo "${2}" | xargs))
  local plugin_tmp_dirs=()
  local plugin_names=()
  local i=0
  for missing_plugin_name in "${plugins_and_sources[@]}"; do
    if [[ $((i % 2)) -eq 0 ]]; then
      local tmp_dir="$(daemon.mktemp_dir)"
      local missing_plugin_source="${plugins_and_sources[$((i + 1))]}"
      local tmp_config_path="${tmp_dir}/solos.config.json"
      local tmp_executable_path="${tmp_dir}/plugin"
      daemon.create_empty_plugin_config "${missing_plugin_source}" "${tmp_config_path}" || return 1
      daemon.curl_plugin "${missing_plugin_source}" "${tmp_executable_path}" || return 1
      plugin_tmp_dirs+=("${tmp_dir}")
      plugin_names+=("${missing_plugin_name}")
    fi
    i=$((i + 1))
  done
  daemon.move_plugins "${plugins_dir}" "${plugin_tmp_dirs[*]}" "${plugin_names[*]}" || return 1
}
daemon.sync_manifest_sources() {
  local plugins_dir="${1}"
  local plugins_and_sources=($(echo "${2}" | xargs))
  local plugin_tmp_dirs=()
  local plugin_names=()
  local i=0
  for changed_plugin_name in "${plugins_and_sources[@]}"; do
    if [[ $((i % 2)) -eq 0 ]]; then
      local tmp_dir="$(daemon.mktemp_dir)"
      local changed_plugin_source="${plugins_and_sources[$((i + 1))]}"
      local tmp_config_path="${tmp_dir}/solos.config.json"
      local current_config_path="${plugins_dir}/${changed_plugin_name}/solos.config.json"
      if [[ ! -d ${current_config_path} ]]; then
        daemon.create_empty_plugin_config "${changed_plugin_source}" "${tmp_config_path}"
      fi
      cp -f "${current_config_path}" "${tmp_config_path}"
      jq ".source = \"${changed_plugin_source}\"" "${tmp_config_path}" >"${tmp_config_path}.tmp"
      mv "${tmp_config_path}.tmp" "${tmp_config_path}"
      rm -f "${tmp_dir}/plugin.next"
      if ! daemon.curl_plugin "${changed_plugin_source}" "${tmp_dir}/plugin.next"; then
        return 1
      fi
      rm -rf "${tmp_dir}/plugin"
      mv "${tmp_dir}/plugin.next" "${tmp_dir}/plugin"
      plugin_tmp_dirs+=("${tmp_dir}")
      plugin_names+=("${changed_plugin_name}")
      rm -f "${plugins_dir}/${changed_plugin_name}/plugin"
    fi
    i=$((i + 1))
  done
  daemon.move_plugins "${plugins_dir}" "${plugin_tmp_dirs[*]}" "${plugin_names[*]}" || return 1
}
daemon.update_plugins() {
  local plugins_dir="${HOME}/.solos/plugins"
  if [[ ! -f ${daemon__manifest_file} ]]; then
    echo "[]" >"${daemon__manifest_file}"
    daemon.log_verbose "Initialized empty manifest file: ${daemon__manifest_file}"
  fi
  local return_file="$(daemon.mktemp_file)"
  daemon.validate_manifest "${plugins_dir}" >"${return_file}" || return 1
  daemon.log_verbose "Validated manifest against the plugin directory: ${plugins_dir}"
  local returned="$(cat ${return_file})"
  local missing_plugins_and_sources=($(lib.line_to_args "${returned}" "0"))
  local changed_plugins_and_sources=($(lib.line_to_args "${returned}" "1"))
  local tmp_plugins_dir="$(daemon.mktemp_dir)"
  if ! cp -rfa "${plugins_dir}"/. "${tmp_plugins_dir}"/; then
    daemon.log_error "Failed to copy ${plugins_dir} to ${tmp_plugins_dir}"
    return 1
  fi
  local missing_count="${#missing_plugins_and_sources[@]}"
  missing_count=$((missing_count / 2))
  local change_count="${#changed_plugins_and_sources[@]}"
  change_count=$((change_count / 2))
  if [[ ${missing_count} -gt 0 ]]; then
    daemon.log_info "Detected ${missing_count} missing plugins based on the updated manifest."
  fi
  if [[ ${change_count} -gt 0 ]]; then
    daemon.log_info "Detected ${change_count} changed plugins based on the updated manifest."
  fi
  if [[ ${change_count} -eq 0 ]]; then
    daemon.log_info "No missing or changed plugins detected based on the updated manifest."
  fi
  daemon.add_plugins "${tmp_plugins_dir}" "${missing_plugins_and_sources[*]}" || return 1
  daemon.sync_manifest_sources "${tmp_plugins_dir}" "${changed_plugins_and_sources[*]}" || return 1
  return_file="$(daemon.mktemp_file)"
  daemon.validate_manifest "${tmp_plugins_dir}" >"${return_file}" || return 1
  daemon.log_verbose "Validated manifest against updated plugin directory: ${tmp_plugins_dir}"
  returned="$(cat ${return_file})"
  local remaining_missing_plugins_and_sources=($(lib.line_to_args "${returned}" "0"))
  local remaining_changed_plugins_and_sources=($(lib.line_to_args "${returned}" "1"))
  if [[ ${#remaining_missing_plugins_and_sources[@]} -gt 0 ]]; then
    daemon.log_error "Failed to sync manifest sources. Unexpected missing plugins: ${remaining_missing_plugins_and_sources[*]}"
    return 1
  fi
  if [[ ${#remaining_changed_plugins_and_sources[@]} -gt 0 ]]; then
    daemon.log_error "Failed to sync manifest sources. Unexpected changed plugins: ${remaining_changed_plugins_and_sources[*]}"
    return 1
  fi
  if [[ ${missing_count} -gt 0 ]]; then
    daemon.log_verbose "Added ${missing_count} missing plugins based on the updated manifest."
  fi
  if [[ ${change_count} -gt 0 ]]; then
    daemon.log_verbose "Changed ${change_count} changed plugins based on the updated manifest."
  fi
  rm -rf "${plugins_dir}"
  mv "${tmp_plugins_dir}" "${plugins_dir}"
  daemon.log_verbose "Replaced the previous plugins directory: ${plugins_dir} with the updated plugins dir: ${tmp_plugins_dir}"
  rm -f "${daemon__frozen_manifest_file}"
  cp -a "${daemon__manifest_file}" "${daemon__frozen_manifest_file}"
  daemon.log_verbose "Copied the manifest file to the temporary directory to prevent user changes during the daemon execution."
}
daemon.get_merged_asset_args() {
  local plugin_count="${1}"
  local plugin_index="${2}"
  local plugin_expanded_asset_args=($(echo "${3}" | xargs))
  local asset_args=($(echo "${4}" | xargs))
  local plugin_expanded_asset_arg_count="${#plugin_expanded_asset_args[@]}"
  plugin_expanded_asset_arg_count=$((plugin_expanded_asset_arg_count / 3))
  local grouped_plugin_expanded_asset_args=()
  local i=0
  for plugin_expanded_asset_arg in "${plugin_expanded_asset_args[@]}"; do
    if [[ $((i % 3)) -ne 0 ]]; then
      i=$((i + 1))
      continue
    fi
    local src="${plugin_expanded_asset_args[${i}]}"
    if [[ ${src} =~ ^daemon\..* ]]; then
      src=$(eval "${src}")
    fi
    local mount_point="${plugin_expanded_asset_args[$((i + 1))]}"
    local permissions="${plugin_expanded_asset_args[$((i + 2))]}"
    grouped_plugin_expanded_asset_args+=("${src} ${mount_point} ${permissions}")
    i=$((i + 1))
  done
  i=0
  local resolved_asset_args=()
  for asset_arg in "${asset_args[@]}"; do
    if [[ $((i % 3)) -ne 0 ]]; then
      i=$((i + 1))
      continue
    fi
    local src="${asset_args[${i}]}"
    if [[ ${src} =~ ^daemon\..* ]]; then
      src=$(eval "${src}")
    fi
    local mount_point="${asset_args[$((i + 1))]}"
    local permissions="${asset_args[$((i + 2))]}"
    resolved_asset_args+=("${src}" "${mount_point}" "${permissions}")
    i=$((i + 1))
  done
  local grouped_plugin_expanded_asset_args_count="${#grouped_plugin_expanded_asset_args[@]}"
  if [[ ${grouped_plugin_expanded_asset_args_count} -ne ${plugin_count} ]]; then
    daemon.log_error "Unexpected - the number of expanded assets does not match the number of plugins (warning, you'll need coffee and bravery for this one)."
    return 1
  fi
  echo "${resolved_asset_args[@]} ${grouped_plugin_expanded_asset_args[${plugin_index}]}" | xargs
}
daemon.validate_firejail_assets() {
  local asset_firejailed_path="${1}"
  local asset_host_path="${2}"
  local asset_chmod_permission="${3}"
  if [[ -z "${asset_firejailed_path}" ]]; then
    daemon.log_error "Empty firejailed path."
    return 1
  fi
  if [[ ! "${asset_firejailed_path}" =~ ^/ ]]; then
    daemon.log_error "Firejailed path must start with a /"
    return 1
  fi
  if [[ ! "${asset_chmod_permission}" =~ ^[0-7]{3}$ ]]; then
    daemon.log_error "Invalid chmod permission."
    return 1
  fi
  if [[ ! -e ${asset_host_path} ]]; then
    daemon.log_error "Invalid asset host path: ${asset_host_path}"
    return 1
  fi
}
daemon.expand_assets_to_thruples() {
  local expanded_asset=($(echo "${1}" | xargs))
  local expanded_asset_path="${2}"
  local expanded_asset_permission="${3}"
  local plugins=($(echo "${4}" | xargs))
  local plugin_names=($(daemon.plugin_paths_to_names "${plugins[*]}"))
  local expanded_asset_args=()
  local i=0
  for plugin in "${plugins[@]}"; do
    local plugin_expanded_asset="${expanded_asset[${i}]}"
    if [[ -z "${plugin_expanded_asset}" ]]; then
      expanded_asset_args+=("-" "-" "-")
      i=$((i + 1))
      continue
    fi
    expanded_asset_args+=(
      "${expanded_asset[${i}]}"
      "${expanded_asset_path}"
      "${expanded_asset_permission}"
    )
    i=$((i + 1))
  done
  echo "${plugins[*]}" | xargs
  echo "${plugin_names[*]}" | xargs
  echo "${expanded_asset_args[*]}" | xargs
}
daemon.run_in_firejail() {
  local phase="${1}"
  local phase_cache="${2}"
  local plugins=($(echo "${3}" | xargs))
  local asset_args=($(echo "${4}" | xargs))
  local plugin_expanded_asset_args=($(echo "${5}" | xargs))
  local executable_options=($(echo "${6}" | xargs))
  local merge_path="${7}"
  local firejail_options=($(echo "${8}" | xargs))
  local return_code=0
  local aggregated_stdout_file="$(daemon.mktemp_file)"
  local aggregated_stderr_file="$(daemon.mktemp_file)"
  local firejailed_pids=()
  local firejailed_home_dirs=()
  local plugin_stdout_files=()
  local plugin_stderr_files=()
  local plugin_index=0
  local plugin_count="${#plugins[@]}"
  daemon.log_verbose "About to run ${plugin_count} plugins in the ${phase} phase."
  for plugin_path in "${plugins[@]}"; do
    if [[ ! -x ${plugin_path}/plugin ]]; then
      daemon.log_error "${plugin_path}/plugin is not an executable file."
      return 1
    fi
    local plugins_dir="$(dirname "${plugin_path}")"
    local plugin_name="$(daemon.plugin_paths_to_names "${plugins[${plugin_index}]}")"
    local plugin_phase_cache="${phase_cache}/${plugin_name}"
    mkdir -p "${plugin_phase_cache}"
    local merged_asset_args=($(
      daemon.get_merged_asset_args \
        "${plugin_count}" \
        "${plugin_index}" \
        "${plugin_expanded_asset_args[*]}" \
        "${asset_args[*]}"
    ))
    local merged_asset_arg_count="${#merged_asset_args[@]}"
    local firejailed_home_dir="$(daemon.mktemp_dir)"
    local plugin_stdout_file="$(daemon.mktemp_file)"
    local plugin_stderr_file="$(daemon.mktemp_file)"
    local plugin_phase_cache="${phase_cache}/${plugin_name}"
    local firejailed_cache="${firejailed_home_dir}/cache"
    mkdir -p "${firejailed_cache}"
    daemon.fs_bind "${plugin_phase_cache}" "${firejailed_cache}"
    chmod -R 777 "${firejailed_cache}"
    for ((i = 0; i < ${merged_asset_arg_count}; i++)); do
      if [[ $((i % 3)) -ne 0 ]]; then
        continue
      fi
      local asset_host_path="${merged_asset_args[${i}]}"
      local asset_firejailed_path="${merged_asset_args[$((i + 1))]}"
      local asset_chmod_permission="${merged_asset_args[$((i + 2))]}"
      if [[ ${asset_firejailed_path} != "-" ]]; then
        if ! daemon.validate_firejail_assets \
          "${asset_firejailed_path}" \
          "${asset_host_path}" \
          "${asset_chmod_permission}"; then
          return 1
        fi
        daemon.log_verbose "Validated asset: ${asset_host_path} to ${asset_firejailed_path} with permissions ${asset_chmod_permission}"
        local asset_firejailed_path="${firejailed_home_dir}${asset_firejailed_path}"
        if [[ -d ${asset_host_path} ]]; then
          mkdir -p "${asset_firejailed_path}"
          daemon.fs_bind "${asset_host_path}" "${asset_firejailed_path}"
        else
          mkdir -p "$(dirname "${asset_firejailed_path}")"
          daemon.fs_bind "${asset_host_path}" "${asset_firejailed_path}"
        fi
        chmod "${asset_chmod_permission}" "${asset_firejailed_path}"
        daemon.log_verbose "Set permissions of bound asset: ${asset_firejailed_path} to ${asset_chmod_permission}"
      fi
    done
    daemon.fs_bind "${plugin_path}/plugin" "${firejailed_home_dir}/plugin"
    chmod +x "${firejailed_home_dir}/plugin"
    daemon.log_verbose "Made the plugin executable: ${firejailed_home_dir}/plugin"
    local plugin_config_file="${plugin_path}/solos.config.json"
    if [[ ! -f ${plugin_config_file} ]]; then
      echo "{}" >"${plugin_config_file}"
      daemon.log_verbose "Initialized an empty config file: ${plugin_config_file}"
    fi
    daemon.fs_bind "${plugin_config_file}" "${firejailed_home_dir}/solos.config.json"
    if [[ -f ${daemon__frozen_manifest_file} ]]; then
      # TODO: make sure local plugins are included.
      if ! cp -a "${daemon__frozen_manifest_file}" "${firejailed_home_dir}/solos.manifest.json"; then
        daemon.log_error "Failed to copy the manifest file to the firejailed home directory."
        return 1
      fi
      daemon.log_verbose "Copied the manifest file to the firejailed home directory."
    else
      return 1
    fi
    if [[ ! " ${executable_options[@]} " =~ " --phase-configure " ]]; then
      chmod 555 "${firejailed_home_dir}/solos.config.json"
      daemon.log_verbose "Set permissions of ${firejailed_home_dir}/solos.config.json to 555"
    else
      chmod 777 "${firejailed_home_dir}/solos.config.json"
      daemon.log_verbose "Set permissions of ${firejailed_home_dir}/solos.config.json to 777"
    fi
    firejail \
      --quiet \
      --noprofile \
      --private="${firejailed_home_dir}" \
      "${firejail_options[@]}" \
      /root/plugin "${executable_options[@]}" \
      >"${plugin_stdout_file}" 2>"${plugin_stderr_file}" &
    local firejailed_pid=$!
    firejailed_pids+=("${firejailed_pid}")
    firejailed_home_dirs+=("${firejailed_home_dir}")
    plugin_stdout_files+=("${plugin_stdout_file}")
    plugin_stderr_files+=("${plugin_stderr_file}")
    plugin_index=$((plugin_index + 1))
  done
  local firejailed_kills=""
  local firejailed_failures=0
  local i=0
  for firejailed_pid in "${firejailed_pids[@]}"; do
    local plugin_name="$(daemon.plugin_paths_to_names "${plugins[${i}]}")"
    wait "${firejailed_pid}"
    local firejailed_exit_code=$?
    daemon.log_verbose "Plugin ${plugin_name} ran within firejail and returned code: ${firejailed_exit_code}"
    local executable_path="${plugins[${i}]}/plugin"
    local firejailed_home_dir="${firejailed_home_dirs[${i}]}"
    local plugin_stdout_file="${plugin_stdout_files[${i}]}"
    local plugin_stderr_file="${plugin_stderr_files[${i}]}"
    if [[ -f ${plugin_stdout_file} ]]; then
      while IFS= read -r line; do
        echo "(${plugin_name}) ${line}" >>"${aggregated_stdout_file}"
      done <"${plugin_stdout_file}"
      daemon.log_verbose "Detected stdout from ${plugin_name} and added to the aggregated stdout file: ${aggregated_stdout_file}"
    fi
    if [[ -f ${plugin_stderr_file} ]]; then
      while IFS= read -r line; do
        echo "(${plugin_name}) ${line}" >>"${aggregated_stderr_file}"
      done <"${plugin_stderr_file}"
      daemon.log_verbose "Detected stderr from ${plugin_name} and added to the aggregated stderr file: ${aggregated_stderr_file}"
    fi
    if [[ ${firejailed_exit_code} -ne 0 ]]; then
      daemon.log_warn "${phase} phase: ${executable_path} exited with non-zero code: ${firejailed_exit_code}"
      firejailed_failures=$((firejailed_failures + 1))
    fi
    i=$((i + 1))
  done
  i=0
  for plugin_stderr_file in "${plugin_stderr_files[@]}"; do
    local plugin_name="$(daemon.plugin_paths_to_names "${plugins[${i}]}")"
    if grep -q "^SOLOS_PANIC" "${plugin_stderr_file}" >/dev/null 2>/dev/null; then
      firejailed_kills="${firejailed_kills} ${plugin_name}"
      daemon.log_verbose "Detected panic from ${plugin_name} in ${phase} phase."
    fi
    i=$((i + 1))
  done
  firejailed_kills=($(echo "${firejailed_kills}" | xargs))
  for plugin_stdout_file in "${plugin_stdout_files[@]}"; do
    if grep -q "^SOLOS_PANIC" "${plugin_stdout_file}" >/dev/null 2>/dev/null; then
      daemon.log_warn "The plugin ${plugin_name} sent a panic message to stdout. These should be sent to stderr. Will ignore."
    fi
  done
  if [[ ${firejailed_failures} -gt 0 ]]; then
    daemon.log_warn "${firejailed_failures} failure(s) detected in the ${phase} phase."
    return_code="1"
  fi
  if [[ ${#firejailed_kills[@]} -gt 0 ]]; then
    lib.panics_add "plugin_panics_detected" <<EOF
The following plugins panicked: [${firejailed_kills[*]}] in phase: ${phase}

STDERR:
$(cat "${aggregated_stderr_file}")

STDOUT:
$(cat "${aggregated_stdout_file}")

HOW TO FIX:
Once all panic files in ${daemon__panics_dir} are removed (and hopefully resolved!), the daemon will restart all plugins from the beginning.
EOF
    daemon.log_error "${firejailed_kills[*]} panics were detected in the ${phase} phase."
    return_code="151"
  else
    lib.panics_remove "plugin_panics_detected"
  fi
  local host_assets=()
  local i=0
  if [[ -n ${merge_path} ]]; then
    for firejailed_home_dir in "${firejailed_home_dirs[@]}"; do
      local plugin_name="${plugin_names[${i}]}"
      local host_asset="$(daemon.fs_bind_source "${firejailed_home_dir}${merge_path}")"
      host_assets+=("${host_asset}")
      daemon.log_verbose "A host asset was updated: ${host_asset}"
      i=$((i + 1))
    done
  fi
  if ! daemon.fs_unbind_all; then
    daemon.log_error "Failed to unbind all firejailed directories."
    return_code="1"
  fi
  for host_asset in "${host_assets[@]}"; do
    chmod -R 777 "${host_asset}"
    daemon.log_verbose "Reset permissions of the host asset: ${host_asset} to 777"
  done
  echo "${aggregated_stdout_file}" | xargs
  echo "${aggregated_stderr_file}" | xargs
  echo "${host_assets[*]}" | xargs
  echo "${return_code}"
}
# ------------------------------------------------------------------------
#
# ALL PHASES:
#
#-------------------------------------------------------------------------
# CONFIGURE:
# The configure phase is responsible for making any modifications to the config files associated
# with the plugins. This allows for a simple upgrade path for plugins that need to make changes
# to the way they configs are structured but don't want to depend on users to manually update them.
daemon.configure_phase() {
  local phase_cache="${1}"
  local returned="$(
    daemon.expand_assets_to_thruples \
      "" \
      "" \
      "" \
      "${2}"
  )"
  local plugins=($(lib.line_to_args "${returned}" "0"))
  local plugin_names=($(lib.line_to_args "${returned}" "1"))
  local expanded_asset_args=($(lib.line_to_args "${returned}" "2"))
  local executable_options=("--phase-configure")
  local firejail_args=("--net=none")
  local asset_args=()
  returned="$(
    daemon.run_in_firejail \
      "configure" \
      "${phase_cache}" \
      "${plugins[*]}" \
      "${asset_args[*]}" \
      "${expanded_asset_args[*]}" \
      "${executable_options[*]}" \
      "/solos.config.json" \
      "${firejail_args[*]}"
  )"
  local aggregated_stdout_file="$(lib.line_to_args "${returned}" "0")"
  local aggregated_stderr_file="$(lib.line_to_args "${returned}" "1")"
  local return_code="$(lib.line_to_args "${returned}" "3")"
  local i=0
  echo "${aggregated_stdout_file}" | xargs
  echo "${aggregated_stderr_file}" | xargs
  return "${return_code}"
}
# DOWNLOAD:
# The download phase is where plugin authors can pull information from remote resources that they might
# need to process the user's data. This could be anything from downloading a file to making an API request.
daemon.download_phase() {
  local phase_cache="${1}"
  local returned="$(
    daemon.expand_assets_to_thruples \
      "" \
      "" \
      "" \
      "${2}"
  )"
  local plugins=($(lib.line_to_args "${returned}" "0"))
  local plugin_names=($(lib.line_to_args "${returned}" "1"))
  local expanded_asset_args=($(lib.line_to_args "${returned}" "2"))
  local executable_options=("--phase-download")
  local firejail_args=()
  local asset_args=(
    'daemon.mktemp_dir' "/download" "777"
  )
  returned="$(
    daemon.run_in_firejail \
      "download" \
      "${phase_cache}" \
      "${plugins[*]}" \
      "${asset_args[*]}" \
      "${expanded_asset_args[*]}" \
      "${executable_options[*]}" \
      "/download" \
      "${firejail_args[*]}"
  )"
  local aggregated_stdout_file="$(lib.line_to_args "${returned}" "0")"
  local aggregated_stderr_file="$(lib.line_to_args "${returned}" "1")"
  local download_dirs_created_by_plugins=($(lib.line_to_args "${returned}" "2"))
  local return_code="$(lib.line_to_args "${returned}" "3")"
  local merge_dir="$(daemon.mktemp_dir)"
  local return_dirs=()
  local i=0
  for created_download_dir in "${download_dirs_created_by_plugins[@]}"; do
    local merge_location="${merge_dir}/${plugin_names[${i}]}"
    mv "${created_download_dir}" "${merge_location}"
    daemon.log_verbose "Moved ${created_download_dir} to ${merge_location}"
    i=$((i + 1))
  done
  echo "${aggregated_stdout_file}"
  echo "${aggregated_stderr_file}"
  echo "${merge_dir}"
  return "${return_code}"
}
# PROCESS:
# Converts downloaded data and the user's workspace data into a format that can be easily chunked
# or acted upon by plugins.
daemon.process_phase() {
  local phase_cache="${1}"
  local merged_download_dir="${2}"
  local download_dirs=()
  local plugins=($(echo "${3}" | xargs))
  local plugin_names=($(daemon.plugin_paths_to_names "${plugins[*]}"))
  local i=0
  for plugin in "${plugins[@]}"; do
    local plugin_name="${plugin_names[${i}]}"
    download_dirs+=("${merged_download_dir}/${plugin_name}")
    i=$((i + 1))
  done
  local returned="$(
    daemon.expand_assets_to_thruples \
      "${download_dirs[*]}" \
      "/download" \
      "555" \
      "${plugins[*]}"
  )"
  local plugins=($(lib.line_to_args "${returned}" "0"))
  local plugin_names=($(lib.line_to_args "${returned}" "1"))
  local expanded_asset_args=($(lib.line_to_args "${returned}" "2"))
  local executable_options=("--phase-process")
  local firejail_args=("--net=none")
  local asset_args=(
    'daemon.mktemp_file' "/processed.json" "777"
    "${daemon__scrubbed_dir}" "/solos" "555"
    "${merged_download_dir}" "/plugins/download" "555"
  )
  returned="$(
    daemon.run_in_firejail \
      "process" \
      "${phase_cache}" \
      "${plugins[*]}" \
      "${asset_args[*]}" \
      "${expanded_asset_args[*]}" \
      "${executable_options[*]}" \
      "/processed.json" \
      "${firejail_args[*]}"
  )"
  local aggregated_stdout_file="$(lib.line_to_args "${returned}" "0")"
  local aggregated_stderr_file="$(lib.line_to_args "${returned}" "1")"
  local processed_files_created_by_plugins=($(lib.line_to_args "${returned}" "2"))
  local return_code="$(lib.line_to_args "${returned}" "3")"
  local merge_dir="$(daemon.mktemp_dir)"
  local i=0
  for processed_file in "${processed_files_created_by_plugins[@]}"; do
    local output_filename="${plugin_names[${i}]}.json"
    local merge_location="${merge_dir}/${output_filename}"
    mv "${processed_file}" "${merge_location}"
    daemon.log_verbose "Moved ${processed_file} to ${merge_location}"
    i=$((i + 1))
  done
  echo "${aggregated_stdout_file}"
  echo "${aggregated_stderr_file}"
  echo "${merge_dir}"
  return "${return_code}"
}
# CHUNK:
# The chunking phase is where processed data gets converted into pure text checks.
# Network access is fine here since we aren't accessing the scrubbed data.
daemon.chunk_phase() {
  local phase_cache="${1}"
  local merged_processed_dir="${2}"
  local plugins=($(echo "${3}" | xargs))
  local processed_files=()
  local plugin_names=($(daemon.plugin_paths_to_names "${plugins[*]}"))
  local i=0
  for plugin in "${plugins[@]}"; do
    local plugin_name="${plugin_names[${i}]}"
    processed_files+=("${merged_processed_dir}/${plugin_name}.json")
    i=$((i + 1))
  done
  local returned="$(
    daemon.expand_assets_to_thruples \
      "${processed_files[*]}" \
      "/processed.json" \
      "555" \
      "${plugins[*]}"
  )"
  local plugins=($(lib.line_to_args "${returned}" "0"))
  local plugin_names=($(lib.line_to_args "${returned}" "1"))
  local expanded_asset_args=($(lib.line_to_args "${returned}" "2"))
  local executable_options=("--phase-chunk")
  local firejail_args=()
  local asset_args=(
    "daemon.mktemp_file" "/chunks.log" "777"
    "${merged_processed_dir}" "/plugins/processed" "555"
  )
  returned="$(
    daemon.run_in_firejail \
      "chunk" \
      "${phase_cache}" \
      "${plugins[*]}" \
      "${asset_args[*]}" \
      "${expanded_asset_args[*]}" \
      "${executable_options[*]}" \
      "/chunks.log" \
      "${firejail_args[*]}"
  )"
  local aggregated_stdout_file="$(lib.line_to_args "${returned}" "0")"
  local aggregated_stderr_file="$(lib.line_to_args "${returned}" "1")"
  local chunk_log_files_created_by_plugins=($(lib.line_to_args "${returned}" "2"))
  local return_code="$(lib.line_to_args "${returned}" "3")"
  local merge_dir="$(daemon.mktemp_dir)"
  local i=0
  for chunk_log_file in "${chunk_log_files_created_by_plugins[@]}"; do
    local merge_location="${merge_dir}/${plugin_names[${i}]}.log"
    mv "${chunk_log_file}" "${merge_location}"
    daemon.log_verbose "Moved ${chunk_log_file} to ${merge_location}"
    i=$((i + 1))
  done
  echo "${aggregated_stdout_file}"
  echo "${aggregated_stderr_file}"
  echo "${merge_dir}"
  return "${return_code}"
}
# PUBLISH:
# This phase only has access to chunks, not processed data. It is responsible for formatting/uploading
# the chunks to a remote service like a RAG query system, search index, or an archival system.
daemon.publish_phase() {
  local phase_cache="${1}"
  local merged_chunks_dir="${2}"
  local plugins=($(echo "${3}" | xargs))
  local chunk_log_files=()
  local plugin_names=($(daemon.plugin_paths_to_names "${plugins[*]}"))
  local i=0
  for plugin in "${plugins[@]}"; do
    local plugin_name="${plugin_names[${i}]}"
    chunk_log_files+=("${merged_chunks_dir}/${plugin_name}.log")
    i=$((i + 1))
  done
  local returned="$(
    daemon.expand_assets_to_thruples \
      "${chunk_log_files[*]}" \
      "/chunks.log" \
      "555" \
      "${plugins[*]}"
  )"
  local plugins=($(lib.line_to_args "${returned}" "0"))
  local plugin_names=($(lib.line_to_args "${returned}" "1"))
  local expanded_asset_args=($(lib.line_to_args "${returned}" "2"))
  local executable_options=("--phase-publish")
  local firejail_args=()
  local asset_args=(
    "${merged_chunks_dir}" "/plugins/chunks" "555"
  )
  returned="$(
    daemon.run_in_firejail \
      "publish" \
      "${phase_cache}" \
      "${plugins[*]}" \
      "${asset_args[*]}" \
      "${expanded_asset_args[*]}" \
      "${executable_options[*]}" \
      "" \
      "${firejail_args[*]}"
  )"
  local aggregated_stdout_file="$(lib.line_to_args "${returned}" "0")"
  local aggregated_stderr_file="$(lib.line_to_args "${returned}" "1")"
  local return_code="$(lib.line_to_args "${returned}" "3")"
  echo "${aggregated_stdout_file}"
  echo "${aggregated_stderr_file}"
  return "${return_code}"
}
daemon.plugin_runner() {
  local plugins=($(echo "${1}" | xargs))
  local run_type="${2}"

  # Plugin stdout/err logs are written to the archive log at the end of each phase.
  local archive_dir="${HOME}/.solos/data/daemon/archives"
  local archive_log_file="${archive_dir}/$(date +%s%N).log"
  mkdir -p "${archive_dir}"
  touch "${archive_log_file}"
  daemon.log_verbose "Created archive log file: ${archive_log_file}"

  # Define cache directories.
  local configure_cache="${HOME}/.solos/data/daemon/cache/configure"
  local download_cache="${HOME}/.solos/data/daemon/cache/download"
  local process_cache="${HOME}/.solos/data/daemon/cache/process"
  local chunk_cache="${HOME}/.solos/data/daemon/cache/chunk"
  local publish_cache="${HOME}/.solos/data/daemon/cache/publish"
  if [[ ! -d ${configure_cache} ]]; then
    mkdir -p "${configure_cache}"
    daemon.log_verbose "Created configure cache directory: ${configure_cache}"
  fi
  if [[ ! -d ${download_cache} ]]; then
    mkdir -p "${download_cache}"
    daemon.log_verbose "Created download cache directory: ${download_cache}"
  fi
  if [[ ! -d ${process_cache} ]]; then
    mkdir -p "${process_cache}"
    daemon.log_verbose "Created process cache directory: ${process_cache}"
  fi
  if [[ ! -d ${chunk_cache} ]]; then
    mkdir -p "${chunk_cache}"
    daemon.log_verbose "Created chunk cache directory: ${chunk_cache}"
  fi
  if [[ ! -d ${publish_cache} ]]; then
    mkdir -p "${publish_cache}"
    daemon.log_verbose "Created publish cache directory: ${publish_cache}"
  fi
  # If we're running precheck plugins, do the scrubbing.
  if [[ ${run_type} = "precheck" ]]; then
    daemon__scrubbed_dir="$(daemon.scrub)"
    if [[ -z ${daemon__scrubbed_dir} ]]; then
      daemon.log_error "Failed to scrub the mounted volume."
      return 1
    fi
    daemon.log_info "Scrubbed the mounted volume copy: $(daemon.get_host_path "${daemon__scrubbed_dir}")"
  elif [[ -z ${daemon__scrubbed_dir} ]]; then
    daemon.log_error "No scrubbed directory was found. Scrubbing should have happened in the precheck phase."
    return 1
  else
    daemon.log_verbose "Re-using the scrubbed directory from the precheck plugins."
  fi
  # Do the copying in the background while the first two phases: configure and download run.
  mkdir -p "${next_archive_dir}/scrubbed"
  cp -rfa "${daemon__scrubbed_dir}"/. "${next_archive_dir}/scrubbed"/ &
  local backgrounded_scrubbed_cp_pid=$!
  daemon.log_verbose "Archiving the scrubbed mounted volume in the background..."
  # ------------------------------------------------------------------------------------
  #
  # CONFIGURE PHASE:
  # Allow plugins to create a default config if none was provided, or modify the existing
  # one if it detects abnormalities.
  #
  # ------------------------------------------------------------------------------------
  local tmp_stdout="$(daemon.mktemp_file)"
  daemon.configure_phase \
    "${configure_cache}" \
    "${plugins[*]}" \
    >"${tmp_stdout}"
  local return_code="$?"
  if [[ ${return_code} -eq 151 ]]; then
    return "${return_code}"
  fi
  local result="$(cat "${tmp_stdout}" 2>/dev/null || echo "")"
  local aggregated_stdout_file="$(lib.line_to_args "${result}" "0")"
  local aggregated_stderr_file="$(lib.line_to_args "${result}" "1")"
  daemon.stash_plugin_logs "configure" "${archive_log_file}" "${aggregated_stdout_file}" "${aggregated_stderr_file}"
  if [[ ${return_code} -ne 0 ]]; then
    daemon.log_error "The configure phase encountered one or more errors. Code=${return_code}."
    if [[ ${run_type} = "precheck" ]]; then
      daemon.log_error "The precheck phase failed. The daemon will not continue."
      return 1
    fi
  else
    daemon.log_info "The ${run_type} configure phase ran successfully."
  fi
  # ------------------------------------------------------------------------------------
  #
  # DOWNLOAD PHASE:
  # let plugins download anything they need before they gain access to the data.
  #
  # ------------------------------------------------------------------------------------
  local tmp_stdout="$(daemon.mktemp_file)"
  daemon.download_phase \
    "${download_cache}" \
    "${plugins[*]}" \
    >"${tmp_stdout}"
  local return_code="$?"
  if [[ ${return_code} -eq 151 ]]; then
    return "${return_code}"
  fi
  local result="$(cat "${tmp_stdout}" 2>/dev/null || echo "")"
  local aggregated_stdout_file="$(lib.line_to_args "${result}" "0")"
  local aggregated_stderr_file="$(lib.line_to_args "${result}" "1")"
  local merged_download_dir="$(lib.line_to_args "${result}" "2")"
  daemon.stash_plugin_logs "download" "${archive_log_file}" "${aggregated_stdout_file}" "${aggregated_stderr_file}"
  if [[ ${return_code} -ne 0 ]]; then
    daemon.log_error "The download phase encountered one or more errors. Code=${return_code}."
    if [[ ${run_type} = "precheck" ]]; then
      daemon.log_error "The precheck phase failed. The daemon will not continue."
      return 1
    fi
  else
    daemon.log_info "The ${run_type} download phase ran successfully."
  fi
  # ------------------------------------------------------------------------------------
  #
  # PROCESSOR PHASE:
  # Allow all plugins to access the collected data. Any one plugin can access the data
  # generated by another plugin. This is key to allow plugins to work together.
  #
  # ------------------------------------------------------------------------------------
  # Make sure the scrubbed data has been copied before we start the process phase to ensure
  # that we copy the scrubbed data exactly as it was when the process phase started.
  wait "${backgrounded_scrubbed_cp_pid}"
  daemon.log_verbose "Archiving of the scrubbed mounted volume has completed."
  local tmp_stdout="$(daemon.mktemp_file)"
  daemon.process_phase \
    "${process_cache}" \
    "${merged_download_dir}" \
    "${plugins[*]}" \
    >"${tmp_stdout}"
  local return_code="$?"
  if [[ ${return_code} -eq 151 ]]; then
    return "${return_code}"
  fi
  local result="$(cat "${tmp_stdout}" 2>/dev/null || echo "")"
  local aggregated_stdout_file="$(lib.line_to_args "${result}" "0")"
  local aggregated_stderr_file="$(lib.line_to_args "${result}" "1")"
  local merged_processed_dir="$(lib.line_to_args "${result}" "2")"
  daemon.stash_plugin_logs "process" "${archive_log_file}" "${aggregated_stdout_file}" "${aggregated_stderr_file}"
  if [[ ${return_code} -ne 0 ]]; then
    daemon.log_error "The process phase encountered one or more errors (${return_code})."
    if [[ ${run_type} = "precheck" ]]; then
      daemon.log_error "The precheck phase failed. The daemon will not continue."
      return 1
    fi
  else
    daemon.log_info "The ${run_type} process phase ran successfully."
  fi
  # ------------------------------------------------------------------------------------
  #
  # CHUNK PHASE:
  # Converts processed data into pure text chunks.
  #
  # ------------------------------------------------------------------------------------
  local tmp_stdout="$(daemon.mktemp_file)"
  daemon.chunk_phase \
    "${chunk_cache}" \
    "${merged_processed_dir}" \
    "${plugins[*]}" \
    >"${tmp_stdout}"
  local return_code="$?"
  if [[ ${return_code} -eq 151 ]]; then
    return "${return_code}"
  fi
  local result="$(cat "${tmp_stdout}" 2>/dev/null || echo "")"
  local aggregated_stdout_file="$(lib.line_to_args "${result}" "0")"
  local aggregated_stderr_file="$(lib.line_to_args "${result}" "1")"
  local merged_chunks_dir="$(lib.line_to_args "${result}" "2")"
  daemon.stash_plugin_logs "chunk" "${archive_log_file}" "${aggregated_stdout_file}" "${aggregated_stderr_file}"
  if [[ ${return_code} -ne 0 ]]; then
    daemon.log_error "The chunk phase encountered one or more errors. Code=${return_code}."
    if [[ ${run_type} = "precheck" ]]; then
      daemon.log_error "The precheck phase failed. The daemon will not continue."
      return 1
    fi
  else
    daemon.log_info "The ${run_type} chunk phase ran successfully."
  fi
  # ------------------------------------------------------------------------------------
  #
  # PUBLISH PHASE:
  # Any last second processing before the chunks are sent to a remote server,
  # third party LLM, local llm, vector db, etc. Ex: might want to use a low cost
  # LLM to generate keywords for chunks.
  #
  # ------------------------------------------------------------------------------------
  local tmp_stdout="$(daemon.mktemp_file)"
  daemon.publish_phase \
    "${publish_cache}" \
    "${merged_chunks_dir}" \
    "${plugins[*]}" \
    >"${tmp_stdout}"
  local return_code="$?"
  if [[ ${return_code} -eq 151 ]]; then
    return "${return_code}"
  fi
  local result="$(cat "${tmp_stdout}" 2>/dev/null || echo "")"
  local aggregated_stdout_file="$(lib.line_to_args "${result}" "0")"
  local aggregated_stderr_file="$(lib.line_to_args "${result}" "1")"
  daemon.stash_plugin_logs "publish" "${archive_log_file}" "${aggregated_stdout_file}" "${aggregated_stderr_file}"
  if [[ ${return_code} -ne 0 ]]; then
    daemon.log_error "The publish phase encountered one or more errors. Code=${return_code}."
    if [[ ${run_type} = "precheck" ]]; then
      daemon.log_error "The precheck phase failed. The daemon will not continue."
      return 1
    fi
  else
    daemon.log_info "The ${run_type} publish phase ran successfully."
  fi
}
daemon.loop() {
  local is_next_precheck=true
  while true; do
    if [[ ! -z $(ls -A "${daemon__panics_dir}") ]]; then
      daemon.log_error "Panics detected. Will restart the daemon in 20 seconds."
      sleep 20
      continue
    fi
    if ! daemon.fs_unbind_all; then
      daemon.log_error "Failed to unbind all firejailed directories."
      sleep 20
      continue
    fi
    if ! daemon.update_plugins; then
      daemon.log_error "Failed to apply the manifest. Waiting 20 seconds before the next run."
      sleep 20
      continue
    fi
    daemon.status "UP"
    if [[ ${is_next_precheck} = true ]]; then
      plugins=($(daemon.plugin_names_to_paths "${daemon__precheck_plugin_names[*]}"))
      if ! daemon.plugin_runner "${plugins[*]}" "precheck"; then
        daemon.log_error "Precheck loop failed."
        return 1
      else
        daemon.log_info "Precheck loop completed successfully."
        is_next_precheck=false
      fi
    else
      local solos_plugin_names="$(daemon.get_solos_plugin_names)"
      local user_plugin_names="$(daemon.get_user_plugin_names)"
      local plugins=($(daemon.plugin_names_to_paths "${solos_plugin_names[*]} ${user_plugin_names[*]}" | xargs))
      if ! daemon.plugin_runner "${plugins[*]}" "main"; then
        daemon.log_error "Main loop failed."
        return 1
      fi
      daemon.log_info "Main loop completed successfully."
      is_next_precheck=true
    fi
    if ! lib.panics_remove "daemon_too_many_retries"; then
      daemon.log_error "Failed to remove the panic file from the last run."
      return 1
    fi
    # Reset the retry counter since we had a successful run.
    daemon__remaining_retries="${daemon__max_retries}"
    daemon.log_verbose "Reset the retry counter to ${daemon__remaining_retries}."
  done
  return 0
}
daemon.retry() {
  daemon__remaining_retries=$((daemon__remaining_retries - 1))
  if [[ ${daemon__remaining_retries} -eq 0 ]]; then
    daemon.log_error "Killing the daemon due to too many failures."
    lib.panics_add "daemon_too_many_retries" <<EOF
The daemon failed and exited after too many retries. Time of failure: $(date).
EOF
    exit 1
  fi
  daemon.log_info "Restarting the daemon loop."
  daemon.loop
  daemon.retry
}
daemon() {
  # This will make sure that if another daemon is running, we exit.
  if ! daemon.pid; then
    return 1
  fi
  if ! rm -f "${daemon__request_file}"; then
    daemon.log_error "Failed to remove the request file: ${daemon__request_file}."
    return 1
  fi
  # We like to see this when running "daemon status" in our shell.
  daemon.status "UP"
  # The main "loop" that churns through our plugins.
  daemon.loop
  # We define some number of allowed retry attempts in a global var
  # and panic if we were not able to restart the loop.
  daemon.retry
}

daemon.parse_args "$@"
daemon.exit_listener &
daemon
