#!/usr/bin/env bash

track.get_history_count() {
  history | tail -n 1 | tr -s ' ' | xargs | cut -d' ' -f1
}

track__base_dir="${HOME}/.solos/data/track"
track__config_dir="${track__base_dir}/config"
track__std_dir="${track__base_dir}/std"
track__prev_history_count="$(track.get_history_count)"
track__trap_gate_open="t"

mkdir -p "${track__base_dir}"

# Make sure that control-c will cancel the running command while also reseting the trap.
trap 'trap "track.trap" DEBUG; exit 1;' SIGINT

track.print_help() {
  local cmd_name="${1}"
  cat <<EOF

USAGE: ${cmd_name} COMMANDS [ARGS]

DESCRIPTION:

Take a note with the option to add a tag, run the positional args (if supplied), track the output, and take a post-exec note.

OPTIONS:

-n         Note only. Will not prompt for a tag.
-t         Tag only. Will not prompt for a note.
-c         Command only. Will not prompt for a tag or note.

EOF
}
track.init_fs() {
  mkdir -p "${track__config_dir}"
  mkdir -p "${track__std_dir}"
  if [[ ! -f "${track__config_dir}/tags" ]]; then
    {
      echo "<none>"
      echo "<create>"
    } >"${track__config_dir}/tags"
  fi
}
track.disgest_save() {
  local tmp_jq_output_file="$1"
  jq -c '.' <"${tmp_jq_output_file}" >>"${track__base_dir}/master.log"
  rm -f "${tmp_jq_output_file}"
}
track.create_tmp_files() {
  # This is used across several functions so must be global.
  track__working_tmp_dir="$(mktemp -d)"

  local stdout_file="${track__working_tmp_dir}/stdout"
  local stderr_file="${track__working_tmp_dir}/stderr"
  local cmd_file="${track__working_tmp_dir}/cmd"
  local return_code_file="${track__working_tmp_dir}/return_code"
  local stderr_tag_file="${track__working_tmp_dir}/stderr_tag"
  local stdout_tag_file="${track__working_tmp_dir}/stdout_tag"

  rm -f \
    "${stdout_file}" \
    "${stderr_file}" \
    "${cmd_file}" \
    "${return_code_file}" \
    "${stdout_tag_file}" \
    "${stderr_tag_file}"

  touch \
    "${stdout_file}" \
    "${stderr_file}" \
    "${cmd_file}" \
    "${return_code_file}" \
    "${stdout_tag_file}" \
    "${stderr_tag_file}"
}
track.digest() {
  local track_id="${1:-""}"
  local user_note="${2:-""}"
  local user_tag="${3:-""}"
  local should_collect_post_note="${3:-false}"

  local stdout_file="${track__working_tmp_dir}/stdout"
  local stderr_file="${track__working_tmp_dir}/stderr"
  local cmd_file="${track__working_tmp_dir}/cmd"
  local return_code_file="${track__working_tmp_dir}/return_code"

  local tmp_jq_output_file="$(mktemp)"
  echo '{
    "id": "'"${track_id}"'",
    "date": "'"$(date)"'"
  }' | jq '.' >"${tmp_jq_output_file}"
  if [[ -n "${user_tag}" ]]; then
    jq '.user_tag = '"$(echo ''"${user_tag}"'' | jq -R -s '.')"'' "${tmp_jq_output_file}" >"${tmp_jq_output_file}.tmp"
    mv "${tmp_jq_output_file}.tmp" "${tmp_jq_output_file}"
  fi
  if [[ -n "${user_pre_note}" ]]; then
    jq '.user_pre_note = '"$(echo ''"${user_pre_note}"'' | jq -R -s '.')"'' "${tmp_jq_output_file}" >"${tmp_jq_output_file}.tmp"
    mv "${tmp_jq_output_file}.tmp" "${tmp_jq_output_file}"
  fi
  # If the user did not supply a command, they are probably just taking a note via
  # the "tag" command. In this case, only build the json that applies to the notes
  # so that it's more obvious in post processing that no command was run.
  local cmd="$(cat "${cmd_file}" | jq -R -s '.')"
  if [[ -n "${cmd}" ]]; then
    jq '.cmd = '"${cmd}"'' "${tmp_jq_output_file}" >"${tmp_jq_output_file}.tmp"
    mv "${tmp_jq_output_file}.tmp" "${tmp_jq_output_file}"
    jq '.return_code = '"$(cat "${return_code_file}" | jq -R -s '.')"'' "${tmp_jq_output_file}" >"${tmp_jq_output_file}.tmp"
    mv "${tmp_jq_output_file}.tmp" "${tmp_jq_output_file}"
    # We have no control over what bytes are sent to stdout/stderr, so we must
    # assume that binary content is in play and avoid piping to jq's encoder directly.
    # Ex: some image processing tools will output binary data to stdout/stderr.
    mv "${stdout_file}" "${track__std_dir}/${track_id}.out"
    mv "${stderr_file}" "${track__std_dir}/${track_id}.err"
    if [[ ${should_collect_post_note} = true ]]; then
      local user_post_note="$(gum.track_post_note || echo "SOLOS:EXIT:1")"
      if [[ ${user_post_note} != "SOLOS:EXIT:1" ]]; then
        jq '.user_post_note = '"$(echo "${user_post_note}" | jq -R -s '.')"'' "${tmp_jq_output_file}" >"${tmp_jq_output_file}.tmp"
        mv "${tmp_jq_output_file}.tmp" "${tmp_jq_output_file}"
      fi
    fi
  fi
  track.disgest_save "${tmp_jq_output_file}"
}
track.trap_eval() {
  local cmd="${1}"

  local stdout_file="${track__working_tmp_dir}/stdout"
  local stderr_file="${track__working_tmp_dir}/stderr"
  local cmd_file="${track__working_tmp_dir}/cmd"
  local return_code_file="${track__working_tmp_dir}/return_code"
  local return_code=1
  echo "${return_code}" >"${return_code_file}"
  {
    local tty_descriptor="$(tty)"
    touch \
      "${stdout_file}" \
      "${stderr_file}"
    echo "${return_code}" >"${return_code_file}"
    if [[ -n ${cmd} ]]; then
      echo "${cmd}" >"${cmd_file}"
    fi
    exec \
      > >(tee "${stdout_file}") \
      2> >(tee "${stderr_file}" >&2)
    if eval ''"${cmd}"'' <>"${tty_descriptor}" 2<>"${tty_descriptor}"; then
      return_code="${?}"
    fi
    echo "${return_code}" >"${return_code_file}"
  } | cat
  return ${return_code}
}
track.lifecycle_scripts() {
  local lifecycle="${1}"
  local prompt="${2}"

  local lifecycle_scripts=()
  local next_dir="${PWD}"
  if [[ ${next_dir} != "${HOME}/.solos"* ]]; then
    return 0
  fi
  while [[ ${next_dir} != "${HOME}/.solos" ]]; do
    if [[ -f "${next_dir}/solos."${lifecycle}".sh" ]]; then
      lifecycle_scripts=("${next_dir}/solos."${lifecycle}".sh" "${lifecycle_scripts[@]}")
    fi
    next_dir="$(dirname "${next_dir}")"
  done
  for lifecycle_script in "${lifecycle_scripts[@]}"; do
    if ! "${lifecycle_script}" >"${tty_descriptor}" 2>&1; then
      return 151
    fi
  done
  return 0
}
track.trap() {
  # Prevent the trap from applying to the PROMPT_COMMAND script.
  if [[ ${BASH_COMMAND} = "track__trap_gate_open=t" ]]; then
    return 0
  fi

  # Prevent infinite loop bugs.
  trap - DEBUG

  # The existence of the COMP_LINE variable implies that a bash completion is taking place.
  if [[ -n "${COMP_LINE}" ]]; then
    trap 'track.trap' DEBUG
    return 0
  fi

  # Consider the prompt: `ls | grep "foo" | less`:
  # In a normal DEBUG trap, this prompt would trigger three trap invocations, one per - ls, grep, and less.
  # But what we really want is to hit the trap one time for the *entire* set of commands.
  # To do this, we unset some arbitrary variable (ie track__trap_gate_open) on the first trapped command, ls,
  # so that all other piped commands will not execute.
  # Then, instead of actually executing the ls command, we execute the last line of our prompt history, which will
  # contain the entire prompt, including all piped commands, operators, etc.
  if [[ -n "${track__trap_gate_open+set}" ]]; then
    unset track__trap_gate_open

    # If the history count has not changed, we probably issued a signal to the
    # shell rather than a command.
    local curr_history_count="$(track.get_history_count)"
    if [[ "${track__prev_history_count}" -eq "${curr_history_count}" ]]; then
      trap 'track.trap' DEBUG
      return 0
    fi
    track__prev_history_count="${curr_history_count}"

    if [[ -n "${rc__checked_out_project}" ]]; then
      local checked_out_project="$(lib.checked_out_project)"
      if [[ "${rc__checked_out_project}" != "${checked_out_project}" ]]; then
        echo "You have changed projects (${rc__checked_out_project} => ${checked_out_project}) and your shell is no longer up to date." >&2
        echo "Please exit and start a new shell session." >&2
        trap 'track.trap' DEBUG
        return 1
      fi
    fi

    # Pretty sure eval'd commands don't get a tty so we have to manually attach it.
    local tty_descriptor="$(tty)"

    # Remember: $BASH_COMMAND is only going to be the first command in any set of piped commands.
    # So instead of using $BASH_COMMAND, we'll use the history command to get the entire prompt.
    local submitted_prompt="$(history 1 | tr -s " " | cut -d" " -f3-)"

    # Using the "-" prefix tells our shell to skip the trap logic below and run as is. Useful if
    # something goes awry and we need to quickly determine whether or not the trap logic is the issue.
    if [[ ${submitted_prompt} = "- "* ]]; then
      eval "$(echo "${submitted_prompt}" | tr -s ' ' | cut -d' ' -f2-)" <>"${tty_descriptor}" 2<>"${tty_descriptor}"
      panics.print
      trap 'track.trap' DEBUG
      return 1
    fi

    # Avoid tag/tracking stuff for blacklisted commands.
    local blacklist=($(shell.blacklist_cmds))
    for opt_out in "${blacklist[@]}"; do
      if [[ ${submitted_prompt} = "${opt_out} "* ]] || [[ ${submitted_prompt} = "${opt_out}" ]]; then
        if [[ ${submitted_prompt} = *"|"* ]]; then
          break
        fi
        eval "${submitted_prompt}" <>"${tty_descriptor}" 2<>"${tty_descriptor}"
        panics.print
        trap 'track.trap' DEBUG
        return 1
      fi
    done

    # Run user defined preexec functions. If any of them fail, return with the exit code
    # and skip the rest of the trap logic, including the remaining preexec functions.
    local preexecs=()
    if [[ ! -z "${user_preexecs:-}" ]]; then
      preexecs=("${user_preexecs[@]}")
    fi
    if [[ -n ${preexecs[@]} ]]; then
      for preexec_fn in "${preexecs[@]}"; do
        # Fail early since the submitted cmd could depend on setup stuff in preexecs.
        if ! "${preexec_fn}" "${submitted_prompt}" >"${tty_descriptor}" 2>&1; then
          local failed_return_code="${?}"
          trap 'track.trap' DEBUG
          return "${failed_return_code}"
        fi
      done
    fi

    # Execute the preexec scripts associated with the user's working directory.
    # These scripts run in the order of their directory structures, where parents
    # are executed first and children are executed last.
    track.lifecycle_scripts "preexec" "${submitted_prompt}"
    local preexec_return="${PIPESTATUS[0]}"
    local should_skip_tag=false
    # 0 - implies that we are running a blacklisted command and should skip the tag tracking.
    if [[ ${preexec_return} -eq 0 ]]; then
      eval "${submitted_prompt}" <>"${tty_descriptor}" 2<>"${tty_descriptor}"
      panics.print
      should_skip_tag=true
    # 151 - implies that one of the preexec scripts failed.
    elif [[ ${preexec_return} -eq 151 ]]; then
      should_skip_tag=true
    # Internal error so we should not proceed.
    elif [[ ${preexec_return} -ne 1 ]]; then
      echo "Unexpected error: preexec returned an unhandled code: ${preexec_return}" >&2
      trap 'track.trap' DEBUG
      return "${preexec_return}"
    fi

    # Initialize the tmp files, evaluate the submitted command, and digest the results.
    if [[ ${should_skip_tag} = false ]]; then
      local track_id="$(date +%s%N)"
      track.create_tmp_files
      track.trap_eval "${submitted_prompt}"
      track.digest "${track_id}"
      panics.print
    fi

    # User defined postexec functions. If one of them fails, do not execute the rest.
    # But don't allow a failure to revise the final return code.
    local postexecs=()
    if [[ ! -z "${user_postexecs:-}" ]]; then
      postexecs=("${user_postexecs[@]}")
    fi
    if [[ -n ${postexecs[@]} ]]; then
      for postexec_fn in "${postexecs[@]}"; do
        if ! "${postexec_fn}" "${submitted_prompt}" >"${tty_descriptor}" 2>&1; then
          break
        fi
      done
    fi
    track.lifecycle_scripts "postexec" "${submitted_prompt}"
  fi

  # All done, reset the trap and ensure $BASH_COMMAND does not execute.
  trap 'track.trap' DEBUG
  return 1
}
track.install() {
  # Make sure that if the user messes with the PROMPT_COMMAND or debug trap that we
  # fail in an obvious way. If they need these things, the best path forward is to
  # not install the SolOS shell. Not great, but it's the best we can do.
  if [[ "$(trap -p DEBUG)" != "" ]]; then
    echo "DEBUG trap is already set. Will not track command outputs." >&2
    return 1
  fi
  track.init_fs
  PROMPT_COMMAND='track__trap_gate_open=t'
  trap 'track.trap' DEBUG
}
track.apply_tag() {
  local newline=$'\n'
  local tag_choice="$(gum.track_tag_choice "${track__config_dir}/tags")"
  if [[ ${tag_choice} = "<none>" ]] || [[ -z ${tag_choice} ]]; then
    echo ""
  elif [[ ${tag_choice} = "<create>" ]]; then
    local new_tag="$(gum.track_create_tag || echo "")"
    if [[ -n "${new_tag}" ]]; then
      sed -i '1s/^/'"${new_tag}"'\n/' "${track__config_dir}/tags"
      echo "${new_tag}"
    else
      track.apply_tag
    fi
  else
    echo "${tag_choice}"
  fi
}
track.cmd() {
  local cmd_name="${1}"
  shift
  local no_more_opts=false
  local opt_command_only=false
  local opt_tag_only=false
  local opt_note_only=false
  while [[ ${no_more_opts} = false ]]; do
    case $1 in
    --help)
      track.print_help "${cmd_name}"
      return 0
      ;;
    help)
      track.print_help "${cmd_name}"
      return 0
      ;;
    -h)
      track.print_help "${cmd_name}"
      return 0
      ;;
    -t)
      opt_tag_only=true
      shift
      ;;
    -c)
      opt_command_only=true
      shift
      ;;
    -n)
      opt_note_only=true
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      return 1
      ;;
    *)
      no_more_opts=true
      break
      ;;
    esac
  done
  local cmd=""
  if [[ $# > 0 ]]; then
    cmd=''"${*}"''
  fi
  local user_pre_note=""
  if [[ ${opt_tag_only} = false ]] && [[ ${opt_command_only} = false ]]; then
    user_pre_note="$(gum.track_pre_note || echo "SOLOS:EXIT:1")"
    if [[ ${user_pre_note} = "SOLOS:EXIT:1" ]]; then
      return 1
    fi
  fi
  local user_tag=""
  if [[ ${opt_note_only} = false ]] && [[ ${opt_command_only} = false ]]; then
    user_tag="$(track.apply_tag)"
    if [[ ${user_tag} = "SOLOS:EXIT:1" ]]; then
      return 1
    fi
  fi
  local digest_args=(
    "${user_pre_note}"
    "${user_tag}"
    true # tells the digest function to collect a post note
  )
  track.create_tmp_files
  local track_id="$(date +%s%N)"
  if [[ -n "${cmd}" ]]; then
    track.trap_eval "${cmd}"
  fi
  track.digest "${track_id}" "${digest_args[@]}"
}
