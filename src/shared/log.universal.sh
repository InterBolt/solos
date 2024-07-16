#!/usr/bin/env bash

log__logfile=""

log.use() {
  log__logfile="${1}"
  mkdir -p "$(dirname "${log__logfile}")"
  touch "${log__logfile}"
}
log.success() {
  local filename="$(caller | cut -f 2 -d " ")"
  local linenumber="$(caller | cut -f 1 -d " ")"
  local log_msg="${1} source=[${filename}:${linenumber}] date=($(date '+%Y-%m-%d %H:%M:%S'))"
  local print_msg="${1}"
  echo "[SUCCESS] ${log_msg}" >>"${log__logfile}"
  echo -e "\033[1;32m[SUCCESS] \033[0m${print_msg}" >&2
}
log.info() {
  local filename="$(caller | cut -f 2 -d " ")"
  local linenumber="$(caller | cut -f 1 -d " ")"
  local log_msg="${1} source=[${filename}:${linenumber}] date=($(date '+%Y-%m-%d %H:%M:%S'))"
  local print_msg="${1}"
  echo "[INFO] ${log_msg}" >>"${log__logfile}"
  echo -e "\033[1;34m[INFO] \033[0m${print_msg}" >&2
}
log.error() {
  local filename="$(caller | cut -f 2 -d " ")"
  local linenumber="$(caller | cut -f 1 -d " ")"
  local log_msg="${1} source=[${filename}:${linenumber}] date=($(date '+%Y-%m-%d %H:%M:%S'))"
  local print_msg="${1}"
  echo "[ERROR] ${log_msg}" >>"${log__logfile}"
  echo -e "\033[1;31m[ERROR] \033[0m${print_msg}" >&2
}
log.warn() {
  local filename="$(caller | cut -f 2 -d " ")"
  local linenumber="$(caller | cut -f 1 -d " ")"
  local log_msg="${1} source=[${filename}:${linenumber}] date=($(date '+%Y-%m-%d %H:%M:%S'))"
  local print_msg="${1}"
  echo "[WARN] ${log_msg}" >>"${log__logfile}"
  echo -e "\033[1;33m[WARN] \033[0m${print_msg}" >&2
}
