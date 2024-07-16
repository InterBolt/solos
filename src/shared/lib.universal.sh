#!/usr/bin/env bash

lib__data_dir="${HOME}/.solos/data"
lib__panics_dir="${lib__data_dir}/panics"
lib__store_dir="${lib__data_dir}/store"

lib.line_to_args() {
  local input_text="${1:-""}"
  local index="${2:-"0"}"
  if [[ -z "${input_text}" ]]; then
    echo ""
    return 0
  fi
  local lines=()
  while IFS= read -r line; do
    lines+=("${line}")
  done <<<"${input_text}"
  local print_line="${lines[${index}]}"
  echo "${print_line}" | xargs
}
export -f lib.line_to_args

lib.panic_dir_path() {
  echo "${lib__panics_dir}"
}
export -f lib.panic_dir_path

lib.checked_out_project() {
  local checked_out_project="$(cat "${lib__store_dir}/checked_out_project" 2>/dev/null || echo "" | xargs)"
  if [[ -z "${checked_out_project}" ]]; then
    return 1
  fi
  echo "${checked_out_project}"
}
export -f lib.checked_out_project

lib.home_dir_path() {
  local home_dir_path="$(cat "${lib__store_dir}/users_home_dir" 2>/dev/null || echo "" | xargs)"
  if [[ -z "${home_dir_path}" ]]; then
    return 1
  fi
  echo "${home_dir_path}"
}
export -f lib.home_dir_path

lib.panics_add() {
  local msg="$(cat)"
  local key="${1}"
  if [[ -z ${key} ]]; then
    echo "Failed to panic: no key supplied" >&2
    return 1
  fi
  local timestamp="$(date)"
  local panicfile="${lib__panics_dir}/${key}"
  mkdir -p "${lib__panics_dir}"
  cat <<EOF >"${panicfile}"
PANIC: ${msg}

TIME: ${timestamp}
EOF
}

lib.panics_remove() {
  local key="${1}"
  if [[ -z ${key} ]]; then
    echo "Failed to panic: no key supplied" >&2
    return 1
  fi
  local panicfile="${lib__panics_dir}/${key}"
  rm -f "${panicfile}"
}
export -f lib.panics_remove

lib.panics_clear() {
  if [[ ! -d "${lib__panics_dir}" ]]; then
    return 1
  fi
  local panic_count="$(ls -A1 "${lib__panics_dir}" | wc -l)"
  if [[ ${panic_count} -eq 0 ]]; then
    return 1
  fi
  rm -rf "${lib__panics_dir}"
  mkdir -p "${lib__panics_dir}"
  return 0
}
export -f lib.panics_clear

lib.panics_print_all() {
  local panic_files="$(ls -A1 "${lib__panics_dir}" 2>/dev/null)"
  if [[ -z ${panic_files} ]]; then
    return 1
  fi
  while IFS= read -r panicfile; do
    cat "${lib__panics_dir}/${panicfile}"
  done <<<"${panic_files}"
}
export -f lib.panics_print_all

lib.home_to_tilde() {
  local filename="${1}"
  local host="$(lib.home_dir_path)"
  echo "${filename/\/root/\~}"
}
export -f lib.home_to_tilde

lib.enter_to_exit() {
  echo "Press enter to exit..."
  read -r || exit 1
  exit 1
}
export -f lib.enter_to_exit

lib.is_help_cmd() {
  if [[ $1 = "--help" ]] || [[ $1 = "-h" ]] || [[ $1 = "help" ]]; then
    return 0
  else
    return 1
  fi
}
export -f lib.is_help_cmd
