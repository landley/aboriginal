#!/bin/bash

# If run with no arguments, list architectures.

if [ $# -ne 1 ]
then
  echo "Usage: $0 ARCH"
  . sources/include.sh
  read_arch_dir
  
  exit 1
fi

# Download source code and build host tools.

./download.sh || exit 1

# host-tools populates one directory with every command the build needs,
# so we can ditch the old $PATH afterwards.

time ./host-tools.sh || exit 1

echo "=== Building ARCH $1"

# Do we need to build the cross compiler?

if [ -f "build/cross-compiler-$1.tar.bz2" ]
then
  echo "=== Skipping cross-compiler-$1 (already there)"
else
  # If we need to build cross compiler, assume root filesystem is stale.

  rm -rf "build/root-filesystem-$1.tar.bz2"
  time ./cross-compiler.sh $1 || exit 1
fi

# Do we need to build the root filesystem?

if [ -f "build/root-filesystem-$1.tar.bz2" ]
then
  echo "=== Skipping root-filesystem-$1 (already there)"
else
  # If we need to build root filesystem, assume system image is stale.

  rm -rf "build/system-image-$1.tar.bz2"
  time ./root-filesystem.sh $1 || exit 1
fi

if [ -f "build/system-image-$1.tar.bz2" ]
then
  echo "=== Skipping system-image-$1 (already there)"
else
  time ./system-image.sh $1 || exit 1
fi
