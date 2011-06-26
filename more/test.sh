#!/bin/bash

# Run a command with sources/include.sh and an architecture loaded

if [ $# -eq 0 ]
then
  echo "Usage: [STAGE_NAME=...] more/test.sh ARCH COMMAND..." >&2
  exit 1
fi

. sources/include.sh || exit 1

load_target "$1"
shift
eval "$@"
