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

# Optionally, we can build a static compiler via canadian cross.  This is
# built to run on the host system, but statically linked against uClibc
# instead of the host's libraries.  This makes it more portable, and smaller
# than statically linking against glibc would make it.

# We don't autodetect the host because i686 is more portable (running on
# both 64 and 32 bit hosts), but x86_64 is (slightly) faster on a 64 bit host.

if [ ! -z "$STATIC_CROSS_COMPILER_HOST" ]
then

  # These are statically linked against uClibc on the host (for portability),
  # built --with-shared, and have uClibc++ installed.

  # To build each of these we need two existing cross compilers: one for
  # the host (to build the executables) and one for the target (to build
  # the libraries).

  BUILD_STATIC=1 FROM_ARCH="$STATIC_CROSS_HOST" NATIVE_TOOLCHAIN=only \
    STAGE_NAME=cross-static ./root-filesystem.sh $1

  # Replace the dynamic cross compiler with the static one.

  rm -rf "build/cross-compiler-$1" &&
  ln -s "cross-static-$1" "build/cross-compiler-$1" || exit 1
fi

# Optionally, we can build a static native compiler.  (The one in
# root-filesystem is dynamically linked against uClibc, this one can
# presumably be untarred and run on any appropriate host system.)

if [ ! -z "$BUILD_STATIC_NATIVE_COMPILER" ]
then

  # Build static native compilers for each target, possibly in parallel

  BUILD_STATIC=1 NATIVE_TOOLCHAIN=only STAGE_NAME=native-compiler \
      ./root-filesystem.sh $1
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
