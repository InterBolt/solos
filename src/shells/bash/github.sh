#!/usr/bin/env bash

github__config_path="${HOME}/.solos/config"
github__secrets_path="${HOME}/.solos/secrets"

github.print_help() {
  cat <<EOF

USAGE: github

DESCRIPTION:

Setup git using the Github CLI.

EOF
}

github.get_token() {
  local tmp_file="$1"
  local gh_token="$(gum.github_token)"
  if [[ -z ${gh_token} ]]; then
    return 1
  fi
  echo "${gh_token}" >"${tmp_file}"
  if gh auth login --with-token <"${tmp_file}" >/dev/null; then
    shell.log_info "Updated Github token."
  else
    shell.log_error "Failed to authenticate with: ${gh_token}"
    local should_retry="$(gum.confirm_retry)"
    if [[ ${should_retry} = true ]]; then
      echo "" >"${tmp_file}"
      github.get_token "${tmp_file}"
    else
      shell.log_error "Exiting the setup process."
      return 1
    fi
  fi
}
github.get_email() {
  local tmp_file="$1"
  local github_email="$(gum.github_email)"
  if [[ -z ${github_email} ]]; then
    return 1
  fi
  echo "${github_email}" >"${tmp_file}"
  if git config --global user.email "${github_email}"; then
    shell.log_info "Updated git email."
  else
    shell.log_error "Failed to update git user.email to: ${github_email}"
    local should_retry="$(gum.confirm_retry)"
    if [[ ${should_retry} = true ]]; then
      echo "" >"${tmp_file}"
      github.get_email "${tmp_file}"
    else
      shell.log_error "Exiting the setup process."
      return 1
    fi
  fi
}
github.get_name() {
  local tmp_file="$1"
  local github_name="$(gum.github_name)"
  if [[ -z ${github_name} ]]; then
    return 1
  fi
  echo "${github_name}" >"${tmp_file}"
  if git config --global user.name "${github_name}"; then
    shell.log_info "Updated git name."
  else
    shell.log_error "Failed to update git user.name to: ${github_name}"
    local should_retry="$(gum.confirm_retry)"
    if [[ ${should_retry} = true ]]; then
      echo "" >"${tmp_file}"
      github.get_name "${tmp_file}"
    else
      return 1
    fi
  fi
}
github.prompts() {
  mkdir -p "${github__secrets_path}" "${github__config_path}"
  local gh_token_path="${github__secrets_path}/gh_token"
  local gh_name_path="${github__config_path}/gh_name"
  local gh_email_path="${github__config_path}/gh_email"
  if ! github.get_token "${gh_token_path}"; then
    shell.log_error "Failed to get Github token."
    return 1
  fi
  if ! github.get_email "${gh_email_path}"; then
    shell.log_error "Failed to get Github email."
    return 1
  fi
  if ! github.get_name "${gh_name_path}"; then
    shell.log_error "Failed to get Github name."
    return 1
  fi
}
github.install() {
  mkdir -p "${github__secrets_path}" "${github__config_path}"
  local gh_token_path="${github__secrets_path}/gh_token"
  local gh_name_path="${github__config_path}/gh_name"
  local gh_email_path="${github__config_path}/gh_email"
  local gh_token="$(cat "${gh_token_path}" 2>/dev/null || echo "")"
  local gh_email="$(cat "${gh_email_path}" 2>/dev/null || echo "")"
  local gh_name="$(cat "${gh_name_path}" 2>/dev/null || echo "")"
  if [[ -z "${gh_token}" ]]; then
    return 1
  fi
  if [[ -z "${gh_email}" ]]; then
    return 1
  fi
  if [[ -z "${gh_name}" ]]; then
    return 1
  fi
  if ! git config --global user.name "${gh_name}"; then
    shell.log_error "Failed to set git user.name."
    return 1
  fi
  if ! git config --global user.email "${gh_email}"; then
    shell.log_error "Failed to set git user.email."
    return 1
  fi
  if ! gh auth login --with-token <"${gh_token_path}"; then
    shell.log_error "Github CLI failed to authenticate."
    return 1
  fi
  if ! gh auth setup-git; then
    shell.log_error "Github CLI failed to setup."
    return 1
  fi
  echo "Github status - $(gh auth status >/dev/null 2>&1 && echo "Logged in" || echo "Logged out")"
}
github.extensions() {
  if ! gh extension install https://github.com/nektos/gh-act; then
    shell.log_error "Failed to install Github CLI extension: gh-act."
    return 1
  fi
  {
    echo '#!/usr/bin/env bash'
    echo ''
    echo 'gh extension exec act $@'
  } >/usr/local/bin/act
  if ! chmod +x /usr/local/bin/act; then
    shell.log_error "Failed to make act executable."
    return 1
  fi
}
github.cmd() {
  mkdir -p "${github__secrets_path}" "${github__config_path}"
  if lib.is_help_cmd "$1"; then
    github.print_help
    return 0
  fi
  local return_file="$(mktemp)"
  if ! github.prompts; then
    return 1
  fi
  if ! github.install; then
    shell.log_error "Failed to install gh."
    return 1
  fi
  if ! github.extensions; then
    shell.log_error "Failed to install gh extensions."
    return 1
  fi
  shell.log_info "Github setup complete."
}
