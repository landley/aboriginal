#!/bin/bash

# Rerun 

if [ $# -lt 2 ]
then
  echo "usage: more/tweak.sh ARCH STAGE COMMAND..." >&1
  exit 1
fi

[ ! -e "$2".sh ] && echo "No stage $2" >&2 && exit 1
ARCH="$1"
export STAGE_NAME="$2"
shift
shift

NO_CLEANUP=1 more/test.sh "$ARCH" "$@" ";create_stage_tarball"
AFTER="$STAGE_NAME" ./build.sh "$ARCH" "$STAGE_NAME"
