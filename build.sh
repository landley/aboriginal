#!/bin/bash

# Run all the steps needed to build a system image from scratch.

# The default set of stages run by this script is (in order):
#   download, host-tools, simple-cross-compiler, simple-root-filesystem,
#   native-compiler, root-filesystem, system-image.

# That sanitizes the host build environment and builds a cross compiler,
# cross compiles a root filesystem and a native toolchain for the target,
# and finally packages the root filesystem up into a system image bootable
# by qemu.

# The simplest set of stages is:
#   download, simple-cross-compiler, simple-root-filesystem, system-image.
#
# That skips sanitizing the host environment, and skips building the native
# compiler.  It builds a system image containing just enough code to boot to
# a command prompt.  To invoke that, do:
#
#   NO_HOST_TOOLS=1 NO_NATIVE_COMPILER=1 ./build.sh $TARGET

# The optional cross-compiler stage (after simple-cross-compiler but before
# simple-root-filesystem) creates a more powerful and portable cross compiler
# that can be used to cross compile more stuff (if you're into that sort of
# thing).  To enable that:

#   CROSS_HOST_ARCH=i686 ./build.sh $TARGET

# Where "i686" is whichever target you want the new cross compiler to run on.

# Start with some housekeeping stuff.  If this script was run with no
# arguments, list available architectures out of sources/targets.

if [ $# -ne 1 ]
then
  echo "Usage: $0 TARGET"

  echo "Supported architectures:"
  cd sources/targets
  ls

  exit 1
fi
ARCH="$1"

# Use environment variables persistently set in the config file.

[ -e config ] && source config

# Allow the output directory to be overridden.  This hasn't been tested in
# forever and probably doesn't work.

[ -z "$BUILD" ] && BUILD="build"

# Very simple dependency tracking: skip stages that have already been done
# (because the tarball they create is already there).

# If you need to rebuild a stage (and everything after it), delete its
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

if [ -z "$NO_HOST_TOOLS" ]
then
  time ./host-tools.sh || exit 1
fi

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

  # Build the host compiler if necessary

  if ARCH="$CROSS_HOST_ARCH" not_already simple-cross-compiler
  then
    time ./simple-cross-compiler.sh "$CROSS_HOST_ARCH" || exit 1
  fi

  time ./cross-compiler.sh "$ARCH" || exit 1
fi

# Build the basic root filesystem.

if not_already simple-root-filesystem
then
  # If we need to build root filesystem, assume root-filesystem and
  # system-image are stale.

  rm -rf "$BUILD/root-filesystem-$ARCH.tar.bz2"
  rm -rf "$BUILD/system-image-$ARCH.tar.bz2"

  time ./simple-root-filesystem.sh "$ARCH" || exit 1

fi

# Build a native compiler.  It's statically linked by default so it can
# run on an arbitrary host system.

if not_already native-compiler && [ -z "$NO_NATIVE_COMPILER" ]
then
  rm -rf "$BUILD/root-filesystem-$ARCH.tar.bz2"

  time ./native-compiler.sh "$ARCH" || exit 1
fi

# Install the native compiler into the root filesystem, if necessary.

if not_already root-filesystem && [ -z "$NO_NATIVE_COMPILER" ]
then
  rm -rf "$BUILD/system-image-$ARCH.tar.bz2"

  time ./root-filesystem.sh "$ARCH" || exit 1
fi

# Package it up into something qemu can boot.

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

  STAGE_NAME=rw-system-image SYSIMAGE_TYPE=ext2 SYSIMAGE_HDA_MEGS=2048 \
    time ./system-image.sh $1 || exit 1
fi
