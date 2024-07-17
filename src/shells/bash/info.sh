#!/usr/bin/env bash

info.extract_usage_description() {
  local help_output=$(cat)
  if [[ -z ${help_output} ]]; then
    echo "Failed to get usage information - no help output provided"
    return 1
  fi
  local description_line_number=$(echo "${help_output}" | grep -n "^DESCRIPTION:" | cut -d: -f1)
  if [[ -z ${description_line_number} ]]; then
    echo "Failed to get usage information - no description line found in help output"
    return 1
  fi
  local first_description_line=$((description_line_number + 2))
  if [[ -z $(echo "${help_output}" | sed -n "${first_description_line}p") ]]; then
    echo "Failed to get usage information - no description found in help output"
    return 1
  fi
  echo "${help_output}" | cut -d$'\n' -f"${first_description_line}"
}
info.table_format() {
  local headers="$1"
  shift
  local newline=$'\n'
  local output=""
  local idx=0
  local idx_rows=0
  local curr_key=""
  local curr_description=""
  for key_or_description in "$@"; do
    if [[ $((idx % 2)) -eq 0 ]]; then
      curr_key="${key_or_description}"
      curr_description=""
    else
      curr_description="${key_or_description}"
    fi
    if [[ -n ${curr_description} ]]; then
      if [[ ${idx_rows} -eq 0 ]]; then
        output+="${curr_key}^${curr_description}"
      else
        output+="${newline}${curr_key}^${curr_description}"
      fi
      idx_rows=$((idx_rows + 1))
    fi
    idx=$((idx + 1))
  done
  output=$(echo "${output}" | column -t -N "${headers}" -s '^' -o '|')
  IFS=$'\n'
  local lines=""
  for line in ${output}; do
    local c1="$(echo "${line}" | cut -d '|' -f1)"
    local c2="$(echo "${line}" | cut -d '|' -f2 | fold -s -w 80)"
    idx=0
    for description_line in ${c2}; do
      if [[ ${idx} -eq 0 ]]; then
        line="${c1}|${description_line}"
      else
        line+="${IFS}$(printf '%*s' "${#c1}" '')  ${description_line}"
      fi
      idx=$((idx + 1))
    done
    lines+="${line}${IFS}"
  done
  local full_line="$(printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -)"
  local output="$(echo "${lines}" | sed 's/|/  /g' | sed '2s/^/'"${full_line}"'\n/')"
  echo "${output}"
  unset IFS
}
info.cmd() {
  local checked_out_project="$(lib.checked_out_project)"
  local user_plugins_dir="${HOME}/.solos/plugins"
  local user_plugin_paths=()
  local user_plugins=()
  if [[ -d ${user_plugins_dir} ]]; then
    while IFS= read -r user_plugin_path; do
      if [[ ${user_plugin_path} != "${user_plugins_dir}" ]]; then
        user_plugin_paths+=("${user_plugin_path}")
      fi
    done < <(find "${user_plugins_dir}" -maxdepth 1 -type d)
    if [[ ${#user_plugin_paths[@]} -gt 0 ]]; then
      for user_plugin_path in "${user_plugin_paths[@]}"; do
        user_plugin_path="${user_plugin_path/\/root\//\~/}"
        user_plugins+=("$(basename "${user_plugin_path}")" "${user_plugin_path}/solos.config.json")
      done
    fi
  fi
  if [[ ${#user_plugins[@]} -eq 0 ]]; then
    local user_plugins_sections=""
  else
    local newline=$'\n'
    local user_plugins_sections="${newline}$(
      info.table_format \
        "INSTALLED_PLUGINS:" \
        "${user_plugins[@]}"
    )"
  fi
  cat <<EOF

$(
    info.table_format \
      "COMMON COMMANDS:" \
      info "Print info about this shell." \
      app "$(app --help | info.extract_usage_description)" \
      plugins "$(plugins --help | info.extract_usage_description)" \
      track "$(track --help | info.extract_usage_description)" \
      note "An alias of the \`track\` command." \
      github "$(github --help | info.extract_usage_description)"
  )

$(
    info.table_format \
      "ADVANCED COMMANDS:" \
      '-' "Runs its arguments as a command. Avoids pre/post exec functions and output tracking." \
      daemon "$(daemon --help | info.extract_usage_description)" \
      preexec "$(preexec --help | info.extract_usage_description)" \
      postexec "$(postexec --help | info.extract_usage_description)" \
      reload "$(reload --help | info.extract_usage_description)" \
      panics "$(panics --help | info.extract_usage_description)"
  )
${user_plugins_sections}
$(
    info.table_format \
      "ABOUT THIS SHELL:" \
      "About" "An interactive Bash session running inside of a docker container." \
      "Docker Image" "solos-project:${checked_out_project}" \
      "Mounted Volume" "~/.solos" \
      "Bash Version" "${BASH_VERSION}" \
      "Distro" "Debian 12" \
      "SolOS Source Code" "https://github.com/interbolt/solos"
  )

$(
    info.table_format \
      "IMPORTANT FILES/FOLDERS:" \
      'Current project' "~/.solos/projects/${checked_out_project}" \
      'User managed rcfile' "~/.solos/rcfiles/.bashrc" \
      'Internal rcfile' "~/.solos/repo/shells/bash/.bashrc" \
      'Installed Plugins' "~/.solos/plugins"
  )
EOF
}
info.install() {
  cat <<EOF
      
   _____       _  ____   _____ 
  / ____|     | |/ __ \ / ____|
 | (___   ___ | | |  | | (___  
  \___ \ / _ \| | |  | |\___ \ 
  ____) | (_) | | |__| |____) |
 |_____/ \___/|_|\____/|_____/ 
    
$(info.cmd)

EOF
}
