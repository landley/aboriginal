#!/bin/bash

# If run with no arguments, list architectures.

ARCH="$1"

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

not_already()
{
  if [ -f "build/$1-$ARCH.tar.bz2" ]
  then
    echo "=== Skipping $1-$ARCH (already there)"
    return 1
  fi

  return 0
}

echo "=== Building ARCH $1"

# Do we need to build the cross compiler?

# This version is --disable shared, doesn't include uClibc++, and is
# dynamically linked against the host's shared libraries.

if not_already cross-compiler
then
  # If we need to build cross compiler, assume root filesystem is stale.

  rm -rf "build/root-filesystem-$ARCH.tar.bz2"
  time ./cross-compiler.sh "$ARCH" || exit 1
fi

# Optionally, we can build a statically linked compiler via canadian cross.

# We don't autodetect the host because i686 is more portable (running on
# both 64 and 32 bit hosts), but x86_64 is (slightly) faster on a 64 bit host.

if [ ! -z "$STATIC_CROSS_COMPILER_HOST" ] && not_already cross-static
then

  # These are statically linked against uClibc on the host (for portability),
  # built --with-shared, and have uClibc++ installed.

  # To build each of these we need two existing cross compilers: one for
  # the host (to build the executables) and one for the target (to build
  # the libraries).

  BUILD_STATIC=1 FROM_ARCH="$STATIC_CROSS_COMPILER_HOST" NATIVE_TOOLCHAIN=only \
    ROOT_NODIRS=1 STAGE_NAME=cross-static ./root-filesystem.sh "$ARCH"

  # Replace the dynamic cross compiler with the static one so the rest of
  # the build uses the new one.

  rm -rf "build/cross-compiler-$ARCH" &&
  ln -s "cross-static-$ARCH" "build/cross-compiler-$ARCH" || exit 1
fi

# Optionally, we can build a static native compiler.  (The one in
# root-filesystem is dynamically linked against uClibc, this one can
# presumably be untarred and run on any appropriate host system.)

if [ ! -z "$BUILD_STATIC_NATIVE_COMPILER" ] && not_already native-compiler
then

  # Build static native compilers for each target, possibly in parallel

  BUILD_STATIC=1 NATIVE_TOOLCHAIN=only STAGE_NAME=native-compiler \
      ./root-filesystem.sh "$ARCH"
fi

# Do we need to build the root filesystem?

if not_already root-filesystem
then

  # If we need to build root filesystem, assume system image is stale.

  rm -rf "build/system-image-$ARCH.tar.bz2"
  time ./root-filesystem.sh "$ARCH" || exit 1
fi

if not_already system-image
then
  time ./system-image.sh $1 || exit 1
fi

