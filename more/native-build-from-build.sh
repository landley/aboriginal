#!/bin/bash

# Run native build out of build directory, using host-tools.sh if
# available.

PATH="$(pwd)/build/host:$PATH"

X=$(readlink -f "$2" 2>/dev/null)
if [ -z "$X" ]
then
  echo "No control image $2" >&2
  exit 1
fi

cd build/system-image-"$1" && ./native-build.sh "$X"
