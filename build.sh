#!/bin/bash

# If run with no arguments, list architectures.

if [ $# -eq 0 ]
then
  echo "Usage: $0 ARCH [ARCH...]"
  sources/include.sh
  exit 1
fi

# Download source code and build host tools.

./download.sh || exit 1

# host-tools populates one directory with every command the build needs,
# so we can ditch the old $PATH afterwards.

time ./host-tools.sh || exit 1

# Run the steps in order for each architecture listed on the command line
for i in "$@"
do
  echo "=== Building ARCH $i"

  if [ -f "build/cross-compiler-$i.tar.bz2" ]
  then
    echo "=== Skipping cross-compiler-$i (already there)"
  else
    rm -rf "build/root-filesystem-$i.tar.bz2"
    time ./cross-compiler.sh $i || exit 1
  fi
  echo "=== native ($i)"
  if [ -f "build/root-filesystem-$i.tar.bz2" ]
  then
    echo "=== Skipping root-filesystem-$i (already there)"
  else
    rm -rf "build/system-image-$i.tar.bz2"
    time ./root-filesystem.sh $i || exit 1
  fi

  if [ -f "build/system-image-$i.tar.bz2" ]
  then
    echo "=== Skipping system-image-$i (already there)"
  else
    time ./system-image.sh $i || exit 1
  fi
done
