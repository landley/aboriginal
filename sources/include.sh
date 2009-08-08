#!/bin/bash

umask 022

# Tell bash not to cache the $PATH because we modify it.  Without this, bash
# won't find new executables added after startup.
set +h

# Include two other files:

[ -e config ] && source config
source sources/functions.sh

# The rest of this file is devoted to setting environment variables.

unset CFLAGS CXXFLAGS

# What host compiler should we use?

[ -z "$CC" ] && export CC=cc

# How many processors should make -j use?

if [ -z "$CPUS" ]
then
  export CPUS=$(echo /sys/devices/system/cpu/cpu[0-9]* | wc -w)
  [ "$CPUS" -lt 1 ] && CPUS=1
fi

# Where are our working directories?

TOP=`pwd`
export SOURCES="${TOP}/sources"
export SRCDIR="${TOP}/packages"
export BUILD="${TOP}/build"
export HOSTTOOLS="${BUILD}/host"

# Set a default non-arch

ARCH_NAME=host
export WORK="${BUILD}/host-temp"

# Retain old $PATH in case we re-run host-tools.sh with different options.

export OLDPATH="$PATH"

# Adjust $PATH

if [ "$PATH" != "$(hosttools_path)" ]
then
  if [ -f "$HOSTTOOLS/busybox" ]
  then
    PATH="$(hosttools_path)"
  else
    PATH="$(hosttools_path):$PATH"
  fi
fi

# Setup for $RECORD_COMMANDS

# WRAPPY_LOGPATH is set unconditionally in case host-tools.sh needs to
# enable wrapping partway through its own build.  Extra environment variables
# don't actually affect much, it's changing $PATH that changes behavior.

[ -z "$STAGE_NAME" ] && STAGE_NAME=`echo $0 | sed 's@.*/\(.*\)\.sh@\1@'`
[ -z "$WRAPPY_LOGDIR" ] && WRAPPY_LOGDIR="$BUILD"
export WRAPPY_LOGPATH="$WRAPPY_LOGDIR/cmdlines.${STAGE_NAME}.setupfor"
if [ ! -z "$RECORD_COMMANDS" ] && [ -f "$BUILD/wrapdir/wrappy" ]
then
  export WRAPPY_REALPATH="$PATH"
  PATH="$BUILD/wrapdir"
fi

[ ! -z "$BUILD_VERBOSE" ] && VERBOSITY="V=1"

# This is an if instead of && so the exit code of include.sh is reliably 0
if [ ! -z "$BUILD_STATIC" ]
then
  STATIC_FLAGS="--static"
fi
