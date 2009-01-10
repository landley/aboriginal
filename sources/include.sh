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

[ -z "$WRAPPY_LOGDIR" ] && WRAPPY_LOGDIR="$BUILD"

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

STAGE_NAME=`echo $0 | sed 's@.*/\(.*\)\.sh@\1@'`
export WRAPPY_LOGPATH="$WRAPPY_LOGDIR/cmdlines.${STAGE_NAME}.setupfor"
if [ -f "$BUILD/wrapdir/wrappy" ]
then
  export WRAPPY_REALPATH="$PATH"
  PATH="$BUILD/wrapdir"
fi

mkdir -p "${SRCDIR}" || dienow

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

  # Read the relevant config file, iterating to find base architecture if any.

  BASE_ARCH="$ARCH_NAME"
  while [ ! -z "$BASE_ARCH" ]
  do
    export ARCH="$BASE_ARCH"
    BASE_ARCH=""
    if [ -z "$NO_BASE_ARCH" ]
    then
      export CONFIG_DIR="${TOP}/sources/targets/${ARCH}"
      source "${CONFIG_DIR}/details"
    fi
  done

  # Which platform are we building for?

  export WORK="${BUILD}/temp-$ARCH"
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

  export CROSS="${BUILD}/cross-compiler-$ARCH"
  export NATIVE="${BUILD}/mini-native-$ARCH"
  export PATH="${CROSS}/bin:$PATH"

  if [ ! -z "${NATIVE_TOOLSDIR}" ]
  then
    TOOLS="${NATIVE}/tools"
  else
    TOOLS="${NATIVE}/usr"
  fi
else
  HW_ARCH=host
  export WORK="${BUILD}/host-temp"
  mkdir -p "${WORK}" || dienow
fi
