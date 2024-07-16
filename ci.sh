#!/usr/bin/env bash

ci.log_info() {
  echo -e "\033[1;34m[INFO] \033[0m(CI) ${1}"
}
ci.log_error() {
  echo -e "\033[1;31m[ERROR] \033[0m(CI) ${1}" >&2
}

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
CURRENT_COMMIT_HASH="$(git rev-parse HEAD)"
TEMP_BRANCH="ci"

if [[ ${CURRENT_BRANCH} != "${TEMP_BRANCH}" ]]; then
  if ! git branch -D "${TEMP_BRANCH}" 2>/dev/null; then
    ci.log_info "No existing \"${TEMP_BRANCH}\" branch to delete."
  else
    ci.log_info "Deleted existing \"${TEMP_BRANCH}\" branch."
  fi
  ci.log_info "Currently checked out \"${CURRENT_BRANCH}\" - will create a temporary commit on the \"${TEMP_BRANCH}\" branch and push changes to trigger the Github workflow."
  if ! git add . &>/dev/null; then
    ci.log_error "No changes to ${TEMP_BRANCH}."
  else
    ci.log_info "Staged changes."
  fi
  if ! git commit -m "CI: ci changes for testing" &>/dev/null; then
    ci.log_error "No changes to commit."
  else
    ci.log_info "Committed changes for the temp ${TEMP_BRANCH} branch."
  fi
  if ! git checkout -b "${TEMP_BRANCH}" &>/dev/null; then
    ci.log_error "Failed to create a new branch called \"${TEMP_BRANCH}\"."
    exit 1
  else
    ci.log_info "Created the new temp branch \"${TEMP_BRANCH}\"."
  fi
  if ! git push -f origin "${TEMP_BRANCH}" &>/dev/null; then
    ci.log_error "Failed to push the \"${TEMP_BRANCH}\" branch to the remote."
    exit 1
  else
    ci.log_info "Pushed the \"${TEMP_BRANCH}\" branch to the remote."
  fi
  if ! git checkout "${CURRENT_BRANCH}" &>/dev/null; then
    ci.log_error "Failed to checkout \"${CURRENT_BRANCH}\""
    exit 1
  else
    ci.log_info "Checked out \"${CURRENT_BRANCH}\""
  fi
  ci.log_info "Resetting to the original commit hash: ${CURRENT_COMMIT_HASH}"
  if ! git reset --soft "${CURRENT_COMMIT_HASH}" &>/dev/null; then
    ci.log_error "Failed to reset to the original commit hash: ${CURRENT_COMMIT_HASH}"
    exit 1
  else
    ci.log_info "Reset to \"${CURRENT_COMMIT_HASH}\" before the temp commit."
  fi
  if ! git branch -D "${TEMP_BRANCH}" &>/dev/null; then
    ci.log_error "Failed to delete the \"${TEMP_BRANCH}\" branch."
    exit 1
  else
    ci.log_info "Deleted the temp branch \"${TEMP_BRANCH}\"."
  fi
else
  ci.log_error "You should never be working on the \"${TEMP_BRANCH}\" branch. Fix this issue and try again."
fi
