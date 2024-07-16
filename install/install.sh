#!/usr/bin/env bash

install.log_info() {
  echo -e "\033[1;34m[INFO] \033[0m(INSTALLER) ${1}" >&2
}
install.log_error() {
  echo -e "\033[1;31m[ERROR] \033[0m(INSTALLER) ${1}" >&2
}

# Make sure the user has what they need on their host system before installing SolOS.
if ! command -v git >/dev/null; then
  install.log_error "Git is required to install SolOS. Please install it and try again."
  exit 1
fi
if ! command -v bash >/dev/null; then
  install.log_error "Bash is required to install SolOS. Please install it and try again."
  exit 1
fi
if ! command -v docker >/dev/null; then
  install.log_error "Docker is required to install SolOS. Please install it and try again."
  exit 1
fi
if ! command -v code >/dev/null; then
  install.log_error "VS Code is required to install SolOS. Please install it and try again."
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  install.log_error "Docker is not running. Please start Docker and try again."
  exit 1
fi

SOURCE_MIGRATIONS_DIR="${HOME}/.solos/repo/install/migrations"
USR_BIN_FILE="/usr/local/bin/solos"
SOURCE_BIN_FILE="${HOME}/.solos/repo/src/bin/host.sh"
ORIGIN_REPO="https://github.com/InterBolt/solos.git"
SOURCE_REPO="${ORIGIN_REPO}"
TMP_DIR="$(mktemp -d 2>/dev/null)"
SOLOS_DIR="${HOME}/.solos"
DEV_MODE=false
DEV_MODE_SETUP_SCRIPT="${SOLOS_DIR}/repo/dev/scripts/dev-mode-setup.sh"
SOLOS_SOURCE_DIR="${SOLOS_DIR}/repo"

# Allow some of the variables to be overridden based on the command line arguments.
while [[ $# -gt 0 ]]; do
  case "${1}" in
  --dev)
    DEV_MODE=true
    shift
    ;;
  --repo=*)
    SOURCE_REPO="${1#*=}"
    if [[ ! ${SOURCE_REPO} =~ ^http ]]; then
      if [[ ! -d ${SOURCE_REPO} ]]; then
        install.log_error "The specified repository does not exist: --repo=\"${SOURCE_REPO}\""
        exit 1
      fi
    fi
    shift
    ;;
  *)
    install.log_error "Unknown arg ${1}"
    exit 1
    ;;
  esac
done

# Create the ~/.solos directory where everything will live.
if [[ ! -d ${SOLOS_DIR} ]]; then
  if ! mkdir -p "${SOLOS_DIR}"; then
    install.log_error "Failed to create ${SOLOS_DIR}"
    exit 1
  fi
fi

# Attempt a git pull if .solos/repo already exists and then exit if it fails.
# This seems like a reasonable default behavior that will prevent important unstaged
# changes from being overwritten.
if [[ -d ${SOLOS_SOURCE_DIR} ]]; then
  if ! git -C "${SOLOS_SOURCE_DIR}" pull >/dev/null 2>&1; then
    install.log_error "Failed to do a \`git pull\` in ${SOLOS_SOURCE_DIR}"
    exit 1
  fi
fi

# Either clone the source repo or copy it from the specified directory.
# Prefer copying for local repos because it's more intuitive to include unstaged changes.
if ! mkdir -p "${SOLOS_SOURCE_DIR}"; then
  install.log_error "Failed to create ${SOLOS_SOURCE_DIR}"
  exit 1
elif [[ -d ${SOURCE_REPO} ]]; then
  cp -r "${SOURCE_REPO}/." "${SOLOS_SOURCE_DIR}/"
elif ! git clone "${SOURCE_REPO}" "${TMP_DIR}/repo" >/dev/null; then
  install.log_error "Failed to clone ${SOURCE_REPO} to ${TMP_DIR}/repo"
  exit 1
elif ! git -C "${TMP_DIR}/repo" remote set-url origin "${ORIGIN_REPO}"; then
  install.log_error "Failed to set the origin to ${ORIGIN_REPO}"
  exit 1
elif ! cp -r "${TMP_DIR}/repo/." "${SOLOS_SOURCE_DIR}/" >/dev/null 2>&1; then
  install.log_error "Failed to copy ${TMP_DIR}/repo to ${SOLOS_SOURCE_DIR}"
  exit 1
fi
install.log_info "Prepared the SolOS source code at ${SOLOS_SOURCE_DIR}"

# Make everything executable.
find "${SOLOS_SOURCE_DIR}" -type f -exec chmod +x {} \;

# Run migrations so that this script can handle installations and updates.
for migration_file in "${SOURCE_MIGRATIONS_DIR}"/*; do
  if ! "${migration_file}"; then
    install.log_error "Migration failed: ${migration_file}"
    exit 1
  fi
done

if ! chmod +x "${SOURCE_BIN_FILE}"; then
  install.log_error "Failed to make ${USR_BIN_FILE} executable."
  exit 1
fi
install.log_info "Made ${SOURCE_BIN_FILE} executable."
rm -f "${USR_BIN_FILE}"
if ! ln -sfv "${SOURCE_BIN_FILE}" "${USR_BIN_FILE}" >/dev/null; then
  install.log_error "Failed to symlink the host bin script."
  exit 1
fi
install.log_info "Symlinked ${USR_BIN_FILE} to ${SOURCE_BIN_FILE}"
if ! chmod +x "${USR_BIN_FILE}"; then
  install.log_error "Failed to make ${USR_BIN_FILE} executable."
  exit 1
fi
install.log_info "Made ${USR_BIN_FILE} executable."

# Run the dev mode setup script, which will add some reasonable starter folders, files, and scripts.
if [[ ${DEV_MODE} = true ]]; then
  install.log_info "Dev mode is ON - seeding the \$HOME/.solos directory."
  export FORCE_REBUILD=false
  if ! "${DEV_MODE_SETUP_SCRIPT}" >/dev/null; then
    install.log_error "Failed to run SolOS dev-mode setup script."
    exit 1
  else
    install.log_info "Ran the SolOS dev-mode setup script."
  fi
else
  install.log_info "Dev mode is OFF - setting up a non-dev installation."
  export FORCE_REBUILD=true
fi

# Confirms that the symlink worked AND that our container will build, run, and accept commands.
if ! solos noop; then
  install.log_error "Failed to run SolOS cli after installing it."
  exit 1
fi
cat <<EOF
$(printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -)
SolOS is ready! Type \`solos --help\` to get started.

Source code: ${ORIGIN_REPO}
Author: Colin Campbell - cc13.engineering@gmail.com
$(printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -)
EOF
