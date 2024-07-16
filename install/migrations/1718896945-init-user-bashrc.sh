#!/usr/bin/env bash

. "${HOME}/.solos/repo/src/shared/log.universal.sh" || exit 1

log.info() {
  local msg="(MIGRATION:HOST) ${1}"
  echo -e "\033[1;34m[INFO] \033[0m${msg}" >&2
}

SOLOS_DIR="${HOME}/.solos"
RCFILES_DIR="${SOLOS_DIR}/rcfiles"
USER_MANAGED_BASHRC_FILE="${RCFILES_DIR}/.bashrc"

# Initialize a bashrc file which allows the user to customize their shell.
if [[ ! -f "${USER_MANAGED_BASHRC_FILE}" ]]; then
  if [[ ! -d ${RCFILES_DIR} ]]; then
    if ! mkdir -p "${RCFILES_DIR}"; then
      echo "Failed to create ${RCFILES_DIR}" >&2
      exit 1
    fi
  fi
  cat <<EOF >"${USER_MANAGED_BASHRC_FILE}"
#!/usr/bin/env bash

. "\${HOME}/.solos/repo/src/shells/bash/.bashrc" "\$@"

# Add your customizations:
EOF
fi

log.info "Completed migration - ${0}"
