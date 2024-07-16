#!/usr/bin/env bash

# Important: these two variables do not follow typical naming conventions
# because it's user-facing.
user_preexecs=()
user_postexecs=()

execs.print_help() {
  local lifecycle="${1}"
  local when=""
  if [[ ${lifecycle} = "preexec" ]]; then
    when="before"
  fi
  if [[ ${lifecycle} = "postexec" ]]; then
    when="after"
  fi
  if [[ -z ${when} ]]; then
    shell.log_error "Unexpected error: lifecycle ${lifecycle}. Cannot generate the help documentation."
    return 1
  fi
  cat <<EOF

USAGE: ${lifecycle} COMMAND [FUNCTION_NAME]

DESCRIPTION:

Manage a list of functions that will run (in the order they are added) \
${when} any entered entered shell prompt (can contain multiple BASH_COMMAND(s) in a single entered prompt). For use in \`~/.solos/rcfiles/.bashrc\`.

COMMANDS:

add <function_name> - Add a function to the ${lifecycle} list.
remove <function_name> - Remove a function from the ${lifecycle} list.
list - List all functions in the ${lifecycle} list.

NOTES:

- When an entered shell prompt matches one of [$(shell.blacklist_cmds)], \
the ${lifecycle} functions will not run.
- The ${lifecycle} functions will run in the order they are added.

EOF
}
execs.already_exists() {
  local lifecycle="${1}"
  local fn="${2}"
  if [[ ${lifecycle} = "preexec" ]] && [[ " ${user_preexecs[@]} " =~ " ${fn} " ]]; then
    return 0
  fi
  if [[ ${lifecycle} = "postexec" ]] && [[ " ${user_postexecs[@]} " =~ " ${fn} " ]]; then
    return 0
  fi
  return 1
}
execs.doesnt_exist() {
  local lifecycle="${1}"
  local fn="${2}"
  if [[ ${lifecycle} = "preexec" ]] && [[ ! " ${user_preexecs[@]} " =~ " ${fn} " ]]; then
    return 0
  fi
  if [[ ${lifecycle} = "postexec" ]] && [[ ! " ${user_postexecs[@]} " =~ " ${fn} " ]]; then
    return 0
  fi
  return 1
}
execs.install() {
  local failed=false
  if ! declare -p user_preexecs >/dev/null 2>&1; then
    shell.log_error "Unexpected error: \`user_preexecs\` is not defined"
    failed=true
  fi
  if ! declare -p user_postexecs >/dev/null 2>&1; then
    shell.log_error "Unexpected error: \`user_postexecs\` is not defined"
    failed=true
  fi
  if [[ ${failed} = true ]]; then
    lib.enter_to_exit
  fi
}
# Uses lots of eval to allow dynamic manipulations of the user_preexecs and user_postexecs arrays.
execs.cmd() {
  local lifecycle="${1}"
  local cmd="${2}"
  local fn="${3}"
  if lib.is_help_cmd "${cmd}"; then
    execs.print_help "${lifecycle}"
    return 0
  fi
  if [[ -z ${cmd} ]]; then
    shell.log_error "Invalid usage: no command supplied to \`${lifecycle}\`."
    execs.print_help "${lifecycle}"
    return 1
  fi
  if [[ ${cmd} = "list" ]]; then
    eval "echo \"\${user_${lifecycle}s[@]}\""
    return 0
  fi
  if [[ ${cmd} = "clear" ]]; then
    eval "user_${lifecycle}s=()"
    return 0
  fi
  if [[ ${cmd} = "remove" ]]; then
    if [[ -z ${fn} ]]; then
      shell.log_error "Invalid usage: missing function name"
      return 1
    fi
    if execs.doesnt_exist "${lifecycle}" "${fn}"; then
      shell.log_warn "'${fn}' does not exist in user_${lifecycle}s."
      return 1
    fi
    if [[ ${lifecycle} = "preexec" ]]; then
      user_preexecs=("${user_preexecs[@]/$fn/}")
      shell.log_info "Removed ${fn} from preexecs."
    fi
    if [[ ${lifecycle} = "postexec" ]]; then
      user_postexecs=("${user_postexecs[@]/$fn/}")
      shell.log_info "Removed ${fn} from postexecs."
    fi
    return 0
  fi
  if [[ ${cmd} = "add" ]]; then
    if [[ -z ${fn} ]]; then
      shell.log_error "Invalid usage: missing function name"
      return 1
    fi
    if execs.already_exists "${lifecycle}" "${fn}"; then
      shell.log_warn "'${fn}' already exists in user_${lifecycle}s."
      return 1
    fi
    if [[ ${lifecycle} = "preexec" ]]; then
      user_preexecs+=("${fn}")
      shell.log_info "Added ${fn} to preexecs."
    fi
    if [[ ${lifecycle} = "postexec" ]]; then
      user_postexecs+=("${fn}")
      shell.log_info "Added ${fn} to postexecs."
    fi
    return 0
  fi
  shell.log_error "Invalid usage: unknown command: ${cmd} supplied to \`${lifecycle}\`."
}
