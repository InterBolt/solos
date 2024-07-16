#!/usr/bin/env bash

plugins__dir="${HOME}/.solos/plugins"
plugins__manifest_file="${plugins__dir}/solos.manifest.json"

plugins.print_help() {
  cat <<EOF

USAGE: plugins COMMAND [NAME] [URL]

DESCRIPTION:

Manage plugins for the current SolOS project. Plugins provide secure data collections for third party systems (ie. LLM RAG dbs, UI dashboards, analytics tools, etc).

COMMANDS:

add          - Add a plugin to the SolOS. If no url is provided, a local plugin is created and initialized with some boilerplate.
remove       - Remove a plugin from the SolOS. To prevent accidental code loss, only non-local plugins can be removed via this command.
               Manual instructions will be printed for removing local plugins.

NOTES:

- Plugins are controlled by a manifest file at: ${plugins__manifest_file}.
- An added plugin will not start running until the current set of plugins have completed all their phases. And a removed plugin will complete any remaining phases before being removed.
- Plugins are run in the order they are added to the manifest file.
- Local plugins are stored at: ${plugins__dir}.

EOF
}
plugins.get_dirnames() {
  local tmp_file="$(mktemp)"
  if ! find "${plugins__dir}" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; >"${tmp_file}"; then
    echo "SOLOS:EXIT:1"
    return 1
  fi
  cat "${tmp_file}" | xargs
}
plugins.cmd() {
  if [[ $# -eq 0 ]]; then
    plugins.print_help
    return 0
  fi
  if lib.is_help_cmd "$1"; then
    plugins.print_help
    return 0
  fi
  local curr_plugin_dirnames="$(plugins.get_dirnames)"
  if [[ ${curr_plugin_dirnames} = "SOLOS:EXIT:1" ]]; then
    shell.log_error "Failed to get the current plugin directories."
    return 1
  fi
  curr_plugin_dirnames=($(echo "${curr_plugin_dirnames}"))
  local arg_cmd="${1}"
  local arg_plugin_name="${2}"
  if [[ -z ${arg_plugin_name} ]]; then
    shell.log_error "Command is required."
    return 1
  fi
  if [[ ${arg_cmd} = "add" ]]; then
    local plugin_url="${3:-""}"
    for plugin_dirname in "${curr_plugin_dirnames[@]}"; do
      if [[ ${plugin_dirname} = ${arg_plugin_name} ]]; then
        shell.log_error "Plugin with the name: ${arg_plugin_name} already exists."
        return 1
      fi
    done
    if [[ -z ${plugin_url} ]]; then
      shell.log_info "Creating a local plugin."
      local checked_out_project="$(lib.checked_out_project)"
      local code_workspace_file="${HOME}/.solos/projects/${checked_out_project}/.vscode/${checked_out_project}.code-workspace"
      if [[ ! -f ${code_workspace_file} ]]; then
        shell.log_error "Code workspace file not found at: ${code_workspace_file}"
        return 1
      fi
      local plugin_path="${plugins__dir}/${arg_plugin_name}"
      if [[ -d "${plugin_path}" ]]; then
        shell.log_error "Plugin directory already exists at: ${plugin_path}"
        return 1
      fi
      local tmp_plugin_dir="$(mktemp -d)"
      local tmp_code_workspace_file="$(mktemp)"
      local host_plugin_path="$(lib.home_to_tilde "${plugin_path}")"
      if ! jq \
        --arg app_name "${arg_plugin_name}" \
        '.folders |= [{ "name": "plugin.'"${arg_plugin_name}"'", "uri": "'"${host_plugin_path}"'", "profile": "shell" }] + .' \
        "${code_workspace_file}" \
        >"${tmp_code_workspace_file}"; then
        shell.log_error "Failed to update the code workspace file: ${code_workspace_file}"
        return 1
      fi
      if ! mkdir "${plugin_path}"; then
        shell.log_error "Failed to create plugin directory at: ${plugin_path}"
        return 1
      fi
      local precheck_plugin_path="${HOME}/.solos/repo/src/daemon/plugins/precheck/plugin"
      if ! cp "${precheck_plugin_path}" "${tmp_plugin_dir}/plugin"; then
        shell.log_error "Failed to copy the precheck plugin to the plugin directory."
        rm -rf "${plugin_path}"
        return 1
      fi
      if ! chmod +x "${tmp_plugin_dir}/plugin"; then
        shell.log_error "Failed to make the plugin executable."
        rm -rf "${plugin_path}"
        return 1
      fi
      # Do the operations.
      cp -rfa "${tmp_plugin_dir}"/. "${plugin_path}/"
      mv "${tmp_code_workspace_file}" "${code_workspace_file}"
      shell.log_info "Reloading the daemon with the new \"${arg_plugin_name}\" plugin (with default precheck template)."
      local full_line="$(printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -)"
      local tmp_stderr="$(mktemp)"
      if ! daemon reload; then
        cat "${tmp_stderr}"
        return 1
      fi
      shell.log_info "Successfully added the plugin: ${arg_plugin_name}"
      cat <<EOF
INSTRUCTIONS:
${full_line}
1. Review the plugin script at ${plugin_path}/plugin to understand how each plugin phase works. \
This script is a copy of the default precheck plugin, which runs in between any two plugin lifecycles.
2. Modify it or overwrite it with your own script or executable.
3. Review your new plugin's logs with \`daemon tail -f\`
${full_line}
EOF
      return 0
    elif [[ ! ${plugin_url} =~ ^http ]]; then
      shell.log_error "The provided plugin URL must start with \"http\"."
      return 1
    else
      local tmp_stderr="$(mktemp)"
      if ! daemon "kill" >/dev/null 2>"${tmp_stderr}"; then
        cat "${tmp_stderr}"
        return 1
      fi
      local tmp_manifest_file="$(mktemp)"
      jq ". += [{\"name\": \"${arg_plugin_name}\", \"source\": \"${plugin_url}\"}]" "${plugins__manifest_file}" >"${tmp_manifest_file}"
      mv "${tmp_manifest_file}" "${plugins__manifest_file}"
      shell.log_info "Added source url to manifest at: ${plugins__manifest_file}"
      if ! daemon reload; then
        return 1
      fi
      shell.log_info "Successfully added the plugin: ${arg_plugin_name}"
      return 0
    fi
  fi
  if [[ ${arg_cmd} = "remove" ]]; then
    if [[ -z ${arg_plugin_name} ]]; then
      shell.log_error "Plugin name is required."
      return 1
    fi
    if [[ ! -d "${plugins__dir}/${arg_plugin_name}" ]]; then
      shell.log_error "Plugin: ${arg_plugin_name} not found in the plugin directory: ${plugins__dir}"
      return 1
    fi
    local plugin_names=($(jq -r '.[].name' "${plugins__manifest_file}"))
    local plugin_sources=($(jq -r '.[].source' "${plugins__manifest_file}"))
    local plugin_found_in_manifest=false
    for plugin_name in "${plugin_names[@]}"; do
      if [[ ${plugin_name} = ${arg_plugin_name} ]]; then
        plugin_found_in_manifest=true
        if [[ ! -d "${plugins__dir}/${plugin_name}" ]]; then
          shell.log_error "Couldn't find the plugin directory: ${plugins__dir}/${plugin_name}"
          return 1
        fi
        break
      fi
    done
    if [[ ${plugin_found_in_manifest} = false ]]; then
      shell.log_warn "Plugin: ${arg_plugin_name} is a locally managed plugin. Manual action required:"
      local full_line="$(printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -)"
      cat <<EOF
INSTRUCTIONS:
${full_line}
1. Kill the daemon: \`daemon kill\`
2. Remove the plugin from the manifest file: ${plugins__manifest_file}
3. Remove the plugin directory: ${plugins__dir}/${arg_plugin_name}
4. Reload the daemon: \`daemon reload\`
${full_line}
EOF
      return 0
    fi
    shell.log_info "Waiting for the daemon to complete its current set of plugins."
    if ! daemon kill; then
      return 1
    fi
    local tmp_manifest_file="$(mktemp)"
    jq "map(select(.name != \"${arg_plugin_name}\"))" "${plugins__manifest_file}" >"${tmp_manifest_file}"
    mv "${tmp_manifest_file}" "${plugins__manifest_file}"
    shell.log_info "Updated manifest at: ${plugins__manifest_file}"
    rm -rf "${plugins__dir}/${arg_plugin_name}"
    shell.log_warn "Deleted plugin directory: ${plugins__dir}/${arg_plugin_name}"
    if ! daemon reload; then
      return 1
    fi
    return 0
  fi
  shell.log_error "Unknown command: ${arg_cmd}"
  return 1
}
