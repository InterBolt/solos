#!/usr/bin/env bash

panics__dir="$(lib.panic_dir_path)"
panics__muted=false

panics.print() {
  if [[ ${panics__muted} = true ]]; then
    echo ""
    return 0
  fi
  local panic_messages="$(lib.panics_print_all)"
  if [[ -z ${panic_messages} ]]; then
    return 1
  fi
  local newline=$'\n'
  gum.danger_box "${panic_messages}${newline}${newline}Please report the issue at https://github.com/interbolt/solos/issues."
  return 0
}
panics.install() {
  if panics.print; then
    local should_proceed="$(gum.confirm_ignore_panic)"
    if [[ ${should_proceed} = true ]]; then
      return 1
    else
      exit 1
    fi
  fi
  return 0
}
panics.print_help() {
  cat <<EOF

USAGE: panic COMMAND [ARGS]

DESCRIPTION:

A command to review "panic" files. These files only exist when the SolOS system is in a "panicked" state.

Panic files at: ${panics__dir}

COMMANDS:

review       - Review the panic messages.
clear        - Clear all panic messages.
mute         - Mute the panic messages.

NOTES:

- Not all panic files will clear on their own, which is why the \`clear\` command exists. \
This is by design to force the user/dev to review and (hopefully) fix the issue that caused the panic.
- Panics are NEVER intended to occur and should be reported here: https://github.com/interbolt/solos/issues.

EOF
}
panics.cmd() {
  if [[ $# -eq 0 ]]; then
    panics.print_help
    return 0
  fi
  if lib.is_help_cmd "$1"; then
    panics.print_help
    return 0
  fi
  if [[ $1 = "review" ]]; then
    if panics.print; then
      return 0
    else
      shell.log_info "No panic message was found."
      return 0
    fi
  elif [[ $1 = "clear" ]]; then
    lib.panics_clear
    return 0
  elif [[ $1 = "mute" ]]; then
    panics__muted=true
    return 0
  else
    shell.log_error "Invalid command: $1"
    panics.print_help
    return 1
  fi
}
