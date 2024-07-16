#!/usr/bin/env bash

bash_completions.install() {
  if [[ -f "/etc/bash_completion" ]]; then
    . /etc/bash_completion
  else
    shell.log_error "bash-completion is not installed"
  fi
  _custom_command_completions() {
    local cur prev words cword
    _init_completion || return
    _command_offset 1
  }
  complete -F _custom_command_completions track
  complete -F _custom_command_completions '-'
}
