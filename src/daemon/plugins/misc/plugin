#!/usr/bin/env bash

plugin.main() {
  if [[ ${1} = "--phase-configure" ]]; then
    echo "Running phase=configure"
  elif [[ ${1} = "--phase-download" ]]; then
    echo "Running phase=download"
  elif [[ ${1} = "--phase-process" ]]; then
    echo "Running phase=process"
  elif [[ ${1} = "--phase-chunk" ]]; then
    echo "Running phase=chunk"
  elif [[ ${1} = "--phase-publish" ]]; then
    echo "Running phase=publish"
  else
    echo "SOLOS_PANIC: unknown phase in arg ${1}" >&2
    exit 1
  fi
}

plugin.main "$@"
