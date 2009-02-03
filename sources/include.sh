#!/bin/bash


[ -e config ] && source config

source sources/functions.sh

# What host compiler should we use?

[ -z "$CC" ] && CC=gcc

# How many processors should make -j use?

if [ -z "$CPUS" ]
then
  export CPUS=$(echo /sys/devices/system/cpu/cpu[0-9]* | wc -w)
  [ "$CPUS" -lt 1 ] && CPUS=1
fi

umask 022
unset CFLAGS CXXFLAGS

# Find/create directories

TOP=`pwd`
export SOURCES="${TOP}/sources"
export SRCDIR="${SOURCES}/packages"
export FROMSRC=../packages
export BUILD="${TOP}/build"
export HOSTTOOLS="${BUILD}/host"

mkdir -p "${SRCDIR}" || dienow

# Adjust $PATH

if [ "$PATH" != "$HOSTTOOLS" ]
then
  if [ -f "$HOSTTOOLS/busybox" ]
  then
    PATH="$HOSTTOOLS"
  else
    PATH="${HOSTTOOLS}:$PATH"
  fi
fi

# Setup for $RECORD_COMMANDS

# WRAPPY_LOGPATH is set unconditionally in case host-tools.sh needs to
# enable wrapping partway through its own build.  Extra environment variables
# don't actually affect much, it's changing $PATH that changes behavior.

STAGE_NAME=`echo $0 | sed 's@.*/\(.*\)\.sh@\1@'`
[ -z "$WRAPPY_LOGDIR" ] && WRAPPY_LOGDIR="$BUILD"
export WRAPPY_LOGPATH="$WRAPPY_LOGDIR/cmdlines.${STAGE_NAME}.setupfor"
if [ ! -z "$RECORD_COMMANDS" ] && [ -f "$BUILD/wrapdir/wrappy" ]
then
  export WRAPPY_REALPATH="$PATH"
  PATH="$BUILD/wrapdir"
fi

# Tell bash not to cache the $PATH because we modify it.  Without this, bash
# won't find new executables added after startup.
set +h

# Get target platform from first command line argument.

if [ -z "$NO_ARCH" ]
then
  ARCH_NAME="$1"
  if [ ! -f "${TOP}/sources/targets/${ARCH_NAME}/details" ]
  then
    echo "Supported architectures: "
    (cd "${TOP}/sources/targets" && ls)
    exit 1
  fi

  # Read the relevant config file.

  ARCH="$ARCH_NAME"
  CONFIG_DIR="${TOP}/sources/targets"
  source "${CONFIG_DIR}/${ARCH}/details"

  # Which platform are we building for?

  export WORK="${BUILD}/temp-$ARCH_NAME"
  rm -rf "${WORK}"
  mkdir -p "${WORK}" || dienow

  # Say "unknown" in two different ways so it doesn't assume we're NOT
  # cross compiling when the host and target are the same processor.  (If host
  # and target match, the binutils/gcc/make builds won't use the cross compiler
  # during mini-native.sh, and the host compiler links binaries against the
  # wrong libc.)
  [ -z "$CROSS_HOST" ] && export CROSS_HOST=`uname -m`-walrus-linux
  [ -z "$CROSS_TARGET" ] && export CROSS_TARGET=${ARCH}-unknown-linux

  # Setup directories and add the cross compiler to the start of the path.

  [ -z "$NATIVE_ROOT" ] && export NATIVE_ROOT="${BUILD}/mini-native-$ARCH"
  export PATH="${BUILD}/cross-compiler-$ARCH/bin:$PATH"

  if [ ! -z "${NATIVE_TOOLSDIR}" ]
  then
    TOOLS="${NATIVE_ROOT}/tools"
  else
    TOOLS="${NATIVE_ROOT}/usr"
  fi
else
  HW_ARCH=host
  export WORK="${BUILD}/host-temp"
  mkdir -p "${WORK}" || dienow
fi
