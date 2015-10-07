#!/bin/bash

# Rerun 

if [ $# -lt 2 ]
then
  echo "usage: more/tweak.sh ARCH STAGE COMMAND..." >&1
  exit 1
fi

[ ! -e "$2".sh ] && echo "No stage $2" >&2 && exit 1
ARCH="$1"
STAGE="$2"
[ "$STAGE" == "native-compiler" ] &&
   STUFF='STAGE_DIR=$STAGE_DIR/usr HOST_ARCH=$ARCH'
shift
shift

NO_CLEANUP=temp STAGE_NAME="$STAGE" more/test.sh "$ARCH" \
  $STUFF "$@" " && create_stage_tarball" || exit 1
NO_CLEANUP=temp AFTER="$STAGE" ./build.sh "$ARCH" "$STAGE"
