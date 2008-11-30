#!/bin/bash


[ -e config ] && source config

source sources/functions.sh

# What host compiler should we use?

[ -z "$CC" ] && CC=gcc

# How many processors should make -j use?

if [ -z "$CPUS" ]
then
  export CPUS=$[$(echo /sys/devices/system/cpu/cpu[0-9]* | wc -w)+0]
  [ "$CPUS" -lt 1 ] && CPUS=1
fi

umask 022
unset CFLAGS CXXFLAGS

# This tells gcc to aggressively garbage collect its internal data
# structures.  Without this, gcc triggers the OOM killer trying to rebuild
# itself in 128 megs of ram, which is the QEMU default size.  Don't do
# this on a 64 bit host or gcc will slow to a crawl due to insufficient memory.
[ "$(uname -m)" != "x86_64" ] &&
  export CFLAGS="--param ggc-min-expand=0 --param ggc-min-heapsize=16384"

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

mkdir -p "${SRCDIR}"

# Tell bash not to cache the $PATH because we modify it.  Without this, bash
# won't find new executables added after startup.
set +h

# Get target platform from first command line argument.

if [ -z "$NO_ARCH" ]
then
  ARCH_NAME="$1"
  ARCH="$(echo "$1" | sed 's@.*/@@')"
  if [ ! -f "${TOP}/sources/targets/${ARCH}/details" ]
  then
    echo "Supported architectures: "
    (cd "${TOP}/sources/targets" && ls)
    exit 1
  fi

  # Read the relevant config file.

  CONFIG_DIR="${TOP}/sources/targets/${ARCH}"
  source "${CONFIG_DIR}/details"

  # Which platform are we building for?

  export WORK="${BUILD}/temp-$ARCH"
  mkdir -p "${WORK}"

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
else
  ARCH_NAME=host
  export WORK="${BUILD}/host-temp"
  mkdir -p "${WORK}"
fi

[ $? -ne 0 ] && dienow

