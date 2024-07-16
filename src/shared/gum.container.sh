#!/usr/bin/env bash

. "${HOME}/.solos/repo/src/shared/lib.universal.sh" || exit 1

# PUBLIC FUNCTIONS:

gum.track_tag_choice() {
  local tags_file="$1"
  local tags="$(cat "${tags_file}")"
  local tags_file=""
  local i=0
  while IFS= read -r line; do
    if [[ -n "${line}" ]]; then
      if [[ ${i} -gt 0 ]]; then
        tags_file+="${newline}${line}"
      else
        tags_file+="${line}"
      fi
      i=$((i + 1))
    fi
  done <<<"${tags}"
  unset IFS
  local user_exit_str="SOLOS:EXIT:1"
  echo "${tags_file}" | gum choose --limit 1 || echo "SOLOS:EXIT:1"
}
gum.track_post_note() {
  gum input --placeholder "Post-command note:"
}
gum.track_create_tag() {
  gum input --placeholder "Enter new tag:"
}
gum.track_pre_note() {
  gum input --placeholder "Enter note"
}
gum.log() {
  local will_print="${1:-true}"
  local log_file="$2"
  local level="$3"
  local msg="$4"
  local source="$5"
  declare -A log_level_colors=(["info"]="#3B78FF" ["tag"]="#0F0" ["debug"]="#A0A" ["error"]="#F02" ["fatal"]="#F02" ["warn"]="#FA0")
  local date="$(date "+%F %T")"
  local source_args=()
  if [[ -n ${source} ]]; then
    source_args=(source "[${source}]")
  fi
  if [[ -t 1 ]] || [[ ${will_print} = true ]]; then
    gum log \
      --level.foreground "${log_level_colors["${level}"]}" \
      --structured \
      --level "${level}" "${msg}"
  fi
  gum log \
    --level.foreground "${log_level_colors["${level}"]}" \
    --file "${log_file}" \
    --structured \
    --level "${level}" "${msg}" "${source_args[@]}" date "${date}"
}
gum.github_token() {
  gum input --password --placeholder "Enter Github access token:"
}
gum.github_email() {
  gum input --placeholder "Enter Github email:"
}
gum.github_name() {
  gum input --placeholder "Enter Github username:"
}
gum.optional_github_repo() {
  local stdout_file="$(mktemp)"
  if ! gum input --placeholder "Enter remote repo (optional):" >"${stdout_file}"; then
    echo "SOLOS:EXIT:1"
  fi
  cat "${stdout_file}"
}
gum.type_to_confirm() {
  local target_input="$1"
  local stdout_file="$(mktemp)"
  if ! gum input --placeholder "Type \"${target_input}\" to confirm:" >"${stdout_file}"; then
    return 1
  fi
  local captured="$(cat "${stdout_file}")"
  if [[ ${captured} != "${target_input}" ]]; then
    return 1
  fi
  return 0
}
gum.confirm_retry() {
  local project_name="$1"
  local project_app="$2"
  if gum confirm \
    "Would you like to retry?" \
    --affirmative="Yes, retry." \
    --negative="No, I'll try again later."; then
    echo "true"
  else
    echo "false"
  fi
}
gum.confirm_ignore_panic() {
  if gum confirm \
    "Would you like to ignore the panic file?" \
    --affirmative="Yes, I know what I'm doing" \
    --negative="No, exit now."; then
    echo "true"
  else
    echo "false"
  fi
}
gum.danger_box() {
  local terminal_width=$(tput cols)
  gum style \
    --foreground "#F02" --border-foreground "#F02" --border thick \
    --width "$((terminal_width - 2))" --align left --margin ".5" --padding "1 2" \
    "$@"
}
gum.success_box() {
  local terminal_width=$(tput cols)
  gum style \
    --foreground "#0F0" --border-foreground "#0F0" --border thick \
    --width "$((terminal_width - 2))" --align left --margin ".5" --padding "1 2" \
    "$@"
}
