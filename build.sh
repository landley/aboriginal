#!/bin/bash

# Run all the steps needed to build a system image from scratch.

# The default set of stages run by this script is (in order):
#   download, host-tools, simple-cross-compiler, root-filesystem,
#   native-compiler, system-image.

# That sanitizes the host build environment and builds a cross compiler,
# cross compiles a root filesystem and a native toolchain for the target,
# and finally packages the root filesystem up into a system image bootable
# by qemu.

# The optional cross-compiler stage (after simple-cross-compiler but before
# root-filesystem) creates a more powerful and portable cross compiler
# that can be used to cross compile more stuff (if you're into that sort of
# thing).  To enable that:

#   CROSS_COMPILER_HOST=i686 ./build.sh $TARGET

# Where "i686" is whichever target you want the new cross compiler to run on.

# The simplest set of stages (if you run them yourself) is:
#   download, simple-cross-compiler, root-filesystem, system-image.

# If this script was run with no arguments, list available architectures

[ ! -z "$2" ] && REBUILD="$2" &&
  [ ! -e "$2".sh ] && echo "no stage $2" && exit 1

if [ $# -lt 1 ] || [ $# -gt 2 ] || [ ! -e sources/targets/"$1" ]
then
  echo
  echo "Usage: $0 TARGET [REBUILD_FROM_STAGE]"
  echo
  echo "Supported architectures:"
  ls sources/targets
  echo
  echo "Build stages:"
  sed -n 's/#.*//;s@.*[.]/\([^.]*\)[.]sh.*@\1@p' "$0" | uniq | xargs echo
  echo

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
  [ "$AGAIN" == "$1" ] && return 0
  [ "$REBUILD" == "$1" ] && zap "$1"

  if [ -f "$BUILD/$1-$ARCH.tar.gz" ]
  then
    echo "=== Skipping $1-$ARCH (already there)"
    return 1
  fi

  return 0
}

zap()
{
  for i in "$@"
  do
    rm -f "$BUILD/$i-$ARCH.tar.gz"
  done
}

do_stage()
{
  STAGE="$1"
  shift

  if [ "$AFTER" == "$STAGE" ]
  then
    unset AFTER
  else
    time ./"$STAGE".sh "$@" || exit 1
  fi
}

# The first two stages (download.sh and host-tools.sh) are architecture
# independent.  In order to allow multiple builds in parallel, re-running
# them after they've already completed must be a safe NOP.

# Download source code.

do_stage download

# Build host tools.  This populates a single directory with every command the
# build needs, so we can ditch the host's $PATH afterwards.

if [ -z "$NO_HOST_TOOLS" ]
then
  do_stage host-tools
fi

# Do we need to build the simple cross compiler?

if not_already simple-cross-compiler
then
  # If we need to build cross compiler, assume root filesystem is stale.

  zap root-filesystem cross-compiler native-compiler system-image

  do_stage simple-cross-compiler "$ARCH"
fi

# Optionally, we can build a more capable statically linked compiler via
# canadian cross.  (It's more powerful than we need here, but if you're going
# to use the cross compiler in other contexts this is probably what you want.)

if [ ! -z "$CROSS_COMPILER_HOST" ] && not_already cross-compiler
then
  zap root-filesystem native-compiler system-image

  # Build the host compiler if necessary

  if ARCH="$CROSS_COMPILER_HOST" not_already simple-cross-compiler
  then
    do_stage simple-cross-compiler "$CROSS_COMPILER_HOST"
  fi

  do_stage cross-compiler "$ARCH"
fi

if ! grep -q KARCH= sources/targets/"$ARCH"
then
  echo no KARCH in $1, stopping here
fi

# Build the basic root filesystem.

if not_already root-filesystem
then
  zap system-image
  [ "$SYSIMAGE_TYPE" == rootfs ] && zap system-image

  do_stage root-filesystem "$ARCH"
fi

# Build a native compiler.  It's statically linked by default so it can
# run on an arbitrary host system.

if not_already native-compiler
then
  zap system-image

  do_stage native-compiler "$ARCH"
fi

# Package it all up into something qemu can boot.

if not_already system-image
then
  do_stage system-image "$ARCH"
fi
