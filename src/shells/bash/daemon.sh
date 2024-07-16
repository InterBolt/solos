#!/usr/bin/env bash

daemon__data_dir="${HOME}/.solos/data/daemon"
daemon__status_file="${daemon__data_dir}/status"
daemon__pid_file="${daemon__data_dir}/pid"
daemon__request_file="${daemon__data_dir}/request"
daemon__log_file="${daemon__data_dir}/master.log"
daemon__mounted_script="/root/.solos/repo/src/daemon/daemon.sh"

daemon.suggested_action_on_error() {
  shell.log_error "Try stopping and deleting the docker container and its associated images before reloading the shell."
  shell.log_error "If the issue persists, please report it here: https://github.com/InterBolt/solos/issues"
}
daemon.kill() {
  local pid="$(cat "${daemon__pid_file}" 2>/dev/null || echo "" | head -n 1 | xargs)"
  if [[ -z ${pid} ]]; then
    shell.log_warn "No daemon process was detected but sending a KILL request anyway."
  fi
  echo "KILL" >"${daemon__request_file}"
  while true; do
    local status="$(cat "${daemon__status_file}" 2>/dev/null || echo "" | head -n 1 | xargs)"
    if [[ ${status} = "DOWN" ]]; then
      break
    fi
    sleep 0.5
  done
  shell.log_info "Killed the daemon."
}
daemon.print_help() {
  cat <<EOF

USAGE: daemon COMMAND [ARGS]

DESCRIPTION:

Some utility commands to manage the daemon process.

COMMANDS:

status      - Show the status of the daemon process.
pid         - Show the PID of the daemon process.
tail        - A wrapper around the unix tail command.
flush       - Prints the logs to stdout before wiping the file.
reload      - Restart the daemon process.
kill        - Kill the daemon process.
foreground  - Run the daemon in the foreground.

NOTES:

- The --verbose flag can be supplied after the \`foreground\` and \`reload\` commands to \
enable verbose logging from the daemon process. Eg. \`daemon foreground --verbose\`.

EOF
}
daemon.cmd() {
  if [[ $# -eq 0 ]]; then
    daemon.print_help
    return 0
  fi
  if lib.is_help_cmd "$1"; then
    daemon.print_help
    return 0
  fi
  if [[ ${1} = "status" ]]; then
    local status="$(cat "${daemon__status_file}" 2>/dev/null || echo "" | head -n 1 | xargs)"
    local pid="$(cat "${daemon__pid_file}" 2>/dev/null || echo "" | head -n 1 | xargs)"
    if [[ -z ${status} ]]; then
      shell.log_error "Unexpected error: the daemon status does not exist."
      daemon.suggested_action_on_error
      return 1
    fi
    local expect_pid="false"
    if [[ ${status} = "UP" ]] || [[ ${status} = "LAUNCHING" ]]; then
      expect_pid="true"
    fi
    if [[ -z ${pid} ]] && [[ ${expect_pid} = true ]]; then
      shell.log_error "Unexpected error: the daemon pid does not exist."
      daemon.suggested_action_on_error
      return 1
    fi
    cat <<EOF
Status: ${status}
PID: ${pid}
Logs: ${daemon__log_file/\/root\//${shell__users_home_dir}\/}
EOF
    return 0
  fi
  if [[ ${1} = "pid" ]]; then
    local pid="$(cat "${daemon__pid_file}" 2>/dev/null || echo "" | head -n 1 | xargs)"
    if [[ -z ${pid} ]]; then
      shell.log_error "Unexpected error: the daemon pid does not exist."
      daemon.suggested_action_on_error
      return 1
    fi
    echo "${pid}"
    return 0
  fi
  if [[ ${1} = "flush" ]]; then
    if [[ ! -f ${daemon__log_file} ]]; then
      shell.log_error "Unexpected error: the daemon logfile does not exist."
      daemon.suggested_action_on_error
      return 1
    fi
    if cat "${daemon__log_file}"; then
      rm -f "${daemon__log_file}"
      touch "${daemon__log_file}"
      return 0
    else
      shell.log_error "Failed to flush the daemon logfile."
      return 1
    fi
  fi
  if [[ ${1} = "tail" ]]; then
    shift
    local tail_args=("$@")
    if [[ ! -f ${daemon__log_file} ]]; then
      shell.log_error "Unexpected error: the daemon logfile does not exist."
      daemon.suggested_action_on_error
      return 1
    fi
    tail "${tail_args[@]}" "${daemon__log_file}" || return 0
    return 0
  fi
  if [[ ${1} = "kill" ]]; then
    shell.log_info "Submitted kill request. Will execute after the daemon completes its current task."
    daemon.kill
    local exit_code=$?
    return "${exit_code}"
  fi
  if [[ ${1} = "reload" ]]; then
    shift
    local daemon_args=("$@")
    shell.log_info "Waiting for the daemon to finish its current task before killing and restarting."
    daemon.kill
    exit_code="$?"
    if [[ ${exit_code} -ne 0 ]]; then
      return "${exit_code}"
    fi
    local container_ctx="/root/.solos"
    local args=(-i -w "${container_ctx}" solos-checked-out-project)
    local bash_args=(-c 'nohup '"${daemon__mounted_script}"' '"${daemon_args[@]}"' >/dev/null 2>&1 &')
    if ! docker exec "${args[@]}" /bin/bash "${bash_args[@]}"; then
      shell.log_error "Failed to reload the daemon process."
      return 1
    fi
    while true; do
      local status="$(cat "${daemon__status_file}" 2>/dev/null || echo "" | head -n 1 | xargs)"
      if [[ ${status} = "UP" ]]; then
        break
      fi
      sleep 0.5
    done
    shell.log_info "Restarted the daemon process."
    return 0
  fi
  if [[ ${1} = "foreground" ]]; then
    shift
    local daemon_args=("$@")
    shell.log_info "Waiting for the daemon to finish its current task before killing and restarting in the foreground."
    daemon.kill
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
      return "${exit_code}"
    fi
    shell.log_info "Starting the daemon process in the foreground."
    local container_ctx="/root/.solos"
    local docker_exec_args=(-it -w "${container_ctx}" solos-checked-out-project)
    local bash_args=(-i -c ''"${daemon__mounted_script}"' '"${daemon_args[@]}"'')
    docker exec "${docker_exec_args[@]}" /bin/bash "${bash_args[@]}"
    local daemon_exit_code="$?"
    if [[ ${daemon_exit_code} -ne 0 ]]; then
      shell.log_error "The daemon process exited with code: ${daemon_exit_code}"
      return 1
    fi
    shell.log_info "The daemon process exited with code: ${daemon_exit_code}"
  fi
  shell.log_error "Unknown command: ${1}"
  return 1
}
