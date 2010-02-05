#!/bin/echo "This file is sourced, not run"

# Set up all the environment variables and functions for a build stage.
# This file is sourced, not run.

# Include config and sources/functions.sh

[ -e config ] && source config

source sources/functions.sh

# List of fallback mirrors to download package source from

MIRROR_LIST="http://impactlinux.com/firmware/mirror http://landley.net/code/firmware/mirror http://127.0.0.1/code/firmware/mirror"

# Where are our working directories?

TOP=`pwd`
export SOURCES="$TOP/sources"
export SRCDIR="$TOP/packages"
export BUILD="$TOP/build"
export HOSTTOOLS="$BUILD/host"
export WRAPDIR="$BUILD/wrapdir"

# Set a default non-arch

export WORK="${BUILD}/host-temp"
export ARCH_NAME=host

# What host compiler should we use?

[ -z "$CC" ] && export CC=cc

# How many processors should make -j use?

MEMTOTAL="$(awk '/MemTotal:/{print $2}' /proc/meminfo)"
if [ -z "$CPUS" ]
then
  export CPUS=$(echo /sys/devices/system/cpu/cpu[0-9]* | wc -w)
  [ "$CPUS" -lt 1 ] && CPUS=1

  # If there's enough memory, try to make CPUs stay busy.

  [ $(($CPUS*512*1024)) -le $MEMTOTAL ] && CPUS=$((($CPUS*3)/2))
fi

[ -z "$STAGE_NAME" ] && STAGE_NAME=`echo $0 | sed 's@.*/\(.*\)\.sh@\1@'`
[ ! -z "$BUILD_VERBOSE" ] && VERBOSITY="V=1"

# Adjust $PATH

export OLDPATH="$PATH"
PATH="$(hosttools_path)"

# If record-commands.sh set up a wrapper directory, adjust $PATH again.
if [ -f "$WRAPDIR/wrappy" ]
then
  export WRAPPY_LOGPATH="$BUILD/logs/cmdlines.$ARCH_NAME.early"
  OLDPATH="$PATH:$OLDPATH"
  PATH="$WRAPDIR"
elif [ ! -f "$HOSTTOOLS/busybox" ] || [ ! -f "$HOSTTOOLS/toybox" ]
then
  PATH="$PATH:$OLDPATH"
fi

# Create files with known permissions
umask 022

# Tell bash not to cache the $PATH because we modify it.  (Without this, bash
# won't find new executables added after startup.)
set +h

# Disable internationalization so sort and sed and such can cope with ASCII.

export LC_ALL=C
