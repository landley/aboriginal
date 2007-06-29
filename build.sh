#!/bin/bash

# If run with no arguments, list architectures.

if [ $# -eq 0 ]
then
  echo "Usage: $0 ARCH [ARCH...]"
  ./include.sh
  exit 1
fi

# Download source code and build host tools.

./download.sh || exit 1
time ./host-tools.sh || exit 1

# Run the steps in order for each architecture listed on the command line
for i in "$@"
do
  echo "=== Building ARCH $i"
  time ./cross-compiler.sh $i || exit 1
  echo "=== native ($i)"
  time ./mini-native.sh $i || exit 1
  time ./package-mini-native.sh $i || exit 1
done
