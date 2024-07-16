#!/usr/bin/env bash

app.print_help() {
  cat <<EOF

USAGE: app COMMAND [NAME]

DESCRIPTION:

Manage apps for the project ($(lib.checked_out_project)).

COMMANDS:

add <name>      - Add an app to the project.
remove <name>   - Remove an app from the project.
list            - List all apps associated with the project.

EOF
}
app.add() {
  local app_name="${1}"
  if [[ -z ${app_name} ]]; then
    shell.log_error "Invalid usage: an app name is required."
    return 1
  fi
  local checked_out_project="$(lib.checked_out_project)"
  local app_dir="${HOME}/.solos/projects/${checked_out_project}/apps/${app_name}"
  local app_dir_on_host="$(lib.home_to_tilde "${app_dir}")"
  if [[ -d "${app_dir}" ]]; then
    shell.log_error "App already exists: ${app_name}"
    return 1
  fi
  local tmp_vscode_workspace_file="$(mktemp)"
  local vscode_workspace_file="${HOME}/.solos/projects/${checked_out_project}/.vscode/${checked_out_project}.code-workspace"
  if ! jq \
    --arg app_name "${app_name}" \
    '.folders |= [{ "name": "app.'"${app_name}"'", "uri": "'"${app_dir_on_host}"'", "profile": "shell" }] + .' \
    "${vscode_workspace_file}" \
    >"${tmp_vscode_workspace_file}"; then
    shell.log_error "Failed to add the app to the code workspace file: ${vscode_workspace_file}"
    return 1
  fi
  local tmp_app_dir="$(mktemp -d)"
  local repo_url="$(gum.optional_github_repo)"
  if [[ ${repo_url} = "SOLOS:EXIT:1" ]]; then
    return 1
  fi
  if [[ -n ${repo_url} ]]; then
    if ! git clone "${repo_url}" "${app_dir}" >/dev/null 2>&1; then
      shell.log_error "Failed to clone the repo: ${repo_url}"
      return 1
    fi
    shell.log_info "Cloned the repo: ${repo_url}"
  fi
  mkdir -p "${app_dir}"
  if [[ -n ${repo_url} ]]; then
    if ! cp -rfa "${tmp_app_dir}"/. "${app_dir}"/; then
      shell.log_error "Failed to move clone app repo to: ${app_dir}"
      return 1
    fi
    shell.log_info "Moved the cloned app repo to: ${app_dir}"
  fi
  cat "${tmp_vscode_workspace_file}" >"${vscode_workspace_file}"
  shell.log_info "Successfully added app at: ${app_dir_on_host}"
}
app.remove() {
  local app_name="${1}"
  if [[ -z ${app_name} ]]; then
    shell.log_error "Invalid usage: an app name is required."
    return 1
  fi
  local checked_out_project="$(lib.checked_out_project)"
  local app_dir="${HOME}/.solos/projects/${checked_out_project}/apps/${app_name}"
  local app_dir_on_host="$(lib.home_to_tilde "${app_dir}")"
  if [[ ! -d "${app_dir}" ]]; then
    shell.log_error "App does not exist: ${app_name}"
    return 1
  fi
  if gum.type_to_confirm "${app_name}"; then
    if ! rm -rf "${app_dir}"; then
      shell.log_error "Failed to remove app: ${app_name}"
      return 1
    fi
    local vscode_workspace_file="${HOME}/.solos/projects/${checked_out_project}/.vscode/${checked_out_project}.code-workspace"
    local tmp_vscode_workspace_file="$(mktemp)"
    if ! jq \
      --arg app_name "${app_name}" \
      'del(.folders[] | select(.name == "app.'"${app_name}"'"))' \
      "${vscode_workspace_file}" \
      >"${tmp_vscode_workspace_file}"; then
      shell.log_error "Failed to remove the app from the code workspace file: ${vscode_workspace_file}"
      return 1
    fi
    cat "${tmp_vscode_workspace_file}" >"${vscode_workspace_file}"
    shell.log_info "Successfully removed app at: ${app_dir_on_host}"
  else
    shell.log_error "Failed to confirm the removal of app: ${app_name}"
    return 1
  fi
}
app.list() {
  local checked_out_project="$(lib.checked_out_project)"
  local checked_out_project_dir="${HOME}/.solos/projects/${checked_out_project}"
  local apps_dir="${checked_out_project_dir}/apps"
  mkdir -p "${apps_dir}"
  local app_dirs=($(find "${apps_dir}" -maxdepth 1 -type d | xargs))
  local count=0
  for app_dir in "${app_dirs[@]}"; do
    if [[ ${app_dir} = "${apps_dir}" ]]; then
      continue
    fi
    echo "${app_dir}"
    count=$((count + 1))
  done
  if [[ ${count} -eq 0 ]]; then
    shell.log_warn "No apps found."
  fi
}
app.cmd() {
  if [[ $# -eq 0 ]]; then
    app.print_help
    return 0
  fi
  if lib.is_help_cmd "${1}"; then
    app.print_help
    return 0
  fi
  if [[ ${1} = "add" ]]; then
    app.add "${2}"
  elif [[ ${1} = "remove" ]]; then
    app.remove "${2}"
  elif [[ ${1} = "list" ]]; then
    app.list
  else
    shell.log_error "Unexpected command: $1"
    return 1
  fi
}
