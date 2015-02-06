#!/bin/bash

# Run native build out of build directory, using host-tools.sh if
# available.

SYSIMG="build/system-image-$1"

if [ ! -e "$SYSIMG" ]
then
  echo "no $SYSIMG" >&2
  exit 1
fi

PATH="$PWD/build/host:$PWD/build/native-compiler-$1:$PATH"

X=$(readlink -f "$2" 2>/dev/null)
if [ -z "$X" ]
then
  echo "No control image $2" >&2
  exit 1
fi

cd "$SYSIMG" && ./native-build.sh "$X"
