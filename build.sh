#!/bin/bash

# Run all the steps needed to build a system image from scratch.

# If run with no arguments, list architectures.

if [ $# -ne 1 ]
then
  echo "Usage: $0 ARCH"
  . sources/include.sh
  read_arch_dir
fi
ARCH="$1"

[ -e config ] && source config

[ -z "$BUILD" ] && BUILD="build"

# A function to skip stages that have already been done (because the
# tarball they create is already there).

not_already()
{
  if [ -f "$BUILD/$1-$ARCH.tar.bz2" ]
  then
    echo "=== Skipping $1-$ARCH (already there)"
    return 1
  fi

  return 0
}

# Download source code and build host tools.

time ./download.sh || exit 1

# host-tools populates one directory with every command the build needs,
# so we can ditch the old $PATH afterwards.

time ./host-tools.sh || exit 1

# Do we need to build the simple cross compiler?

if not_already simple-cross-compiler
then
  # If we need to build cross compiler, assume root filesystem is stale.

  rm -rf "$BUILD/root-filesystem-$ARCH.tar.bz2"
  time ./simple-cross-compiler.sh "$ARCH" || exit 1

  if [ ! -z "$CROSS_SMOKE_TEST" ]
  then
    sources/more/cross-smoke-test.sh "$ARCH" || exit 1
  fi
fi

# Optionally, we can build a more capable statically linked compiler via
# canadian cross.  (It's more powerful than we need here, but if you're going
# to use the cross compiler in other contexts this is probably what you want.)

if [ ! -z "$STATIC_CC_HOST" ] && not_already cross-compiler
then

  # These are statically linked against uClibc on the host (for portability),
  # built --with-shared, and have uClibc++ installed.

  # To build each of these we need two existing cross compilers: one for
  # the host (to build the executables) and one for the target (to build
  # the libraries).

  BUILD_STATIC=1 FROM_ARCH="$STATIC_CC_HOST" STAGE_NAME=cross-compiler \
    ./native-compiler.sh "$ARCH" || exit 1

  if [ ! -z "$CROSS_SMOKE_TEST" ]
  then
    sources/more/cross-smoke-test.sh "$ARCH" || exit 1
  fi
fi

# Build a native compiler.  It's statically linked by default so it can be
# run on an arbitrary host system.

# If this compiler exists, root-filesystem will pick it up and incorpoate it.

if not_already native-compiler && [ -z "$NO_NATIVE_COMPILER" ]
then
  rm -rf "$BUILD/root-filesystem-$ARCH.tar.bz2"

  ./native-compiler.sh "$ARCH" || exit 1
fi

# Do we need to build the root filesystem?

if not_already root-filesystem
then

  # If we need to build root filesystem, assume system image is stale.

  rm -rf "$BUILD/system-image-$ARCH.tar.bz2"
  time ./root-filesystem.sh "$ARCH" || exit 1
fi

if not_already system-image
then
  time ./system-image.sh $1 || exit 1
fi

