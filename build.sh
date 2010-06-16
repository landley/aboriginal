#!/bin/bash

# Run all the steps needed to build a system image from scratch.

# Simplest: download, simple-cross-compiler, simple-root-filesystem,
# system-image.

# More likely: download, host-tools, simple-cross-compiler, cross-compiler,
# native-compiler, simple-root-filesystem, root-filesystem, system-image

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
# tarball they create is already there).  Stages delete the tarballs of
# later stages as a simple form of dependency tracking.

# If you need to rebuild a stage and everything after it, delete its
# tarball out of "build" and re-run build.sh.

not_already()
{
  if [ -f "$BUILD/$1-$ARCH.tar.bz2" ]
  then
    echo "=== Skipping $1-$ARCH (already there)"
    return 1
  fi

  return 0
}

# The first two stages (download.sh and host-tools.sh) are architecture
# independent.  In order to allow multiple builds in parallel, re-running
# them after they've already completed must be a safe NOP.

# Download source code.

time ./download.sh || exit 1

# Build host tools.  This populates a single directory with every command the
# build needs, so we can ditch the host's $PATH afterwards.

time ./host-tools.sh || exit 1

# Do we need to build the simple cross compiler?

if not_already simple-cross-compiler
then
  # If we need to build cross compiler, assume root filesystem is stale.

  rm -rf "$BUILD/simple-root-filesystem-$ARCH.tar.bz2"

  time ./simple-cross-compiler.sh "$ARCH" || exit 1
fi

# Optionally, we can build a more capable statically linked compiler via
# canadian cross.  (It's more powerful than we need here, but if you're going
# to use the cross compiler in other contexts this is probably what you want.)

if [ ! -z "$CROSS_HOST_ARCH" ] && not_already cross-compiler
then
  rm -rf "$BUILD/simple-root-filesystem-$ARCH.tar.bz2"

  ./cross_compiler.sh "$ARCH" || exit 1
fi

# Build a native compiler.  It's statically linked by default so it can
# run on an arbitrary host system.

if not_already native-compiler && [ -z "$NO_NATIVE_COMPILER" ]
then
  rm -rf "$BUILD/root-filesystem-$ARCH.tar.bz2"

  ./native-compiler.sh "$ARCH" || exit 1
fi

# Do we need to build the root filesystem?

if not_already simple-root-filesystem
then
  # If we need to build root filesystem, assume root-filesystem and
  # system-image are stale.

  rm -rf "$BUILD/root-filesystem-$ARCH.tar.bz2"
  rm -rf "$BUILD/system-image-$ARCH.tar.bz2"

  time ./simple-root-filesystem.sh "$ARCH" || exit 1

fi

# Install the native compiler into the root filesystem (if any).

if not_already root-filesystem && [ -z "$NO_NATIVE_COMPILER" ]
then
  rm -rf "$BUILD/system-image-$ARCH.tar.bz2"

  time ./root-filesystem.sh "$ARCH" || exit 1
fi

if not_already system-image
then
  time ./system-image.sh $1 || exit 1
fi

# Optionally build a system image with a writeable root filesystem.

if [ ! -z "$BUILD_RW_SYSTEM_IMAGE" ] && not_already rw-image
then
  # Optimization: don't rebuild kernel if we don't need to.
  mkdir -p "$BUILD/rw-system-image-$ARCH" &&
  cp "$BUILD/system-image-$ARCH"/zImage-* "$BUILD/rw-system-image-$ARCH"

  STAGE_NAME=rw-system-image SYSIMAGE_TYPE=ext2 SYSIMAGE_HDA_MEGS=2048 time ./system-image.sh $1 || exit 1
fi
