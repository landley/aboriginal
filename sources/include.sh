#!/bin/echo "This file is sourced, not run"

if ! already_included_this 2>/dev/null
then
alias already_included_this=true

# Set up all the environment variables and functions for a build stage.
# This file is sourced, not run.

# Include config and source shell function files.

[ -e config ] && source config

source sources/utility_functions.sh
source sources/functions.sh
source sources/download_functions.sh

# Avoid trouble from unexpected environment settings

[ -z "$NO_SANITIZE_ENVIRONMENT" ] && sanitize_environment

# List of fallback mirrors to download package source from

MIRROR_LIST="http://landley.net/code/aboriginal/mirror http://127.0.0.1/code/aboriginal/mirror"

# Where are our working directories?

export_if_blank TOP=`pwd`
export_if_blank SOURCES="$TOP/sources"
export_if_blank SRCDIR="$TOP/packages"
export_if_blank PATCHDIR="$SOURCES/patches"
export_if_blank BUILD="$TOP/build"
export_if_blank SRCTREE="$BUILD/packages"
export_if_blank HOSTTOOLS="$BUILD/host"
export_if_blank WRAPDIR="$BUILD/wrapdir"

# Set a default non-arch

export WORK="${BUILD}/host-temp"
export ARCH_NAME=host

# What host compiler should we use?

export_if_blank CC=cc

# How many processors should make -j use?

MEMTOTAL="$(awk '/MemTotal:/{print $2}' /proc/meminfo)"
if [ -z "$CPUS" ]
then
  export CPUS=$(echo /sys/devices/system/cpu/cpu[0-9]* | wc -w)
  [ "$CPUS" -lt 1 ] && CPUS=1

  # If we're not using hyper-threading, and there's plenty of memory,
  # use 50% more CPUS than we actually have to keep system busy

  [ -z "$(cat /proc/cpuinfo | grep '^flags' | head -n 1 | grep -w ht)" ] &&
    [ $(($CPUS*512*1024)) -le $MEMTOTAL ] &&
      CPUS=$((($CPUS*3)/2))
fi

export_if_blank STAGE_NAME=`echo $0 | sed 's@.*/\(.*\)\.sh@\1@'`
[ ! -z "$BUILD_VERBOSE" ] && VERBOSITY="V=1"

export_if_blank BUILD_STATIC=busybox,binutils,gcc-core,gcc-g++,make

# Adjust $PATH

# If record-commands.sh set up a wrapper directory, adjust $PATH again.
if [ -z "$OLDPATH" ] && [ -f "$WRAPDIR/wrappy" ]
then
  mkdir -p "$BUILD/logs"
  [ $? -ne 0 ] && echo "Bad $WRAPDIR" >&2 && dienow
  export WRAPPY_LOGPATH="$BUILD/logs/cmdlines.$ARCH_NAME.early"
  export OLDPATH="$PATH"
  PATH="$WRAPDIR"
else
  export OLDPATH="$PATH"
  [ ! -f "$HOSTTOOLS/busybox" ] &&
    PATH="$(hosttools_path):$OLDPATH" ||
    PATH="$(hosttools_path)"
fi

# Create files with known permissions
umask 022

# Tell bash not to cache the $PATH because we modify it.  (Without this, bash
# won't find new executables added after startup.)
set +h

# Disable internationalization so sort and sed and such can cope with ASCII.

export LC_ALL=C

fi # already_included_this
