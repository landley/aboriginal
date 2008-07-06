#!/bin/bash

# Setup

# If this is set, mini-native won't include development tools, just uClibc
# and busybox.  (Set it to "headers" to include kernel headers if you'd like
# to add your own toolchain, such as tinycc.)

# export BUILD_SHORT=1

# If this is set, the build records the command lines run by each build into
# log files in the build directory, ala "build/cmdlines.$PACKAGENAME"

# export RECORD_COMMANDS=1

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
  export CFLAGS="--param ggc-min-expand=0 --param ggc-min-heapsize=8192"

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
  if [ ! -f "${TOP}/sources/configs/${ARCH}" ]
  then
    echo "Supported architectures: "
    (cd "${TOP}/sources/configs" && ls)
    exit 1
  fi

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

  # Read the relevant config file.

  source "${TOP}/sources/configs/${ARCH}"

  # Setup directories and add the cross compiler to the start of the path.

  export CROSS="${BUILD}/cross-compiler-$ARCH"
  export NATIVE="${BUILD}/mini-native-$ARCH"
  export PATH="${CROSS}/bin:$PATH"
else
  export WORK="${BUILD}/host-temp"
  mkdir -p "${WORK}"
fi

[ $? -ne 0 ] && dienow

# Everything after here is utility functions used by the other scripts.

# Strip the version number off a tarball

function cleanup()
{
  if [ $? -ne 0 ]
  then
    dienow
  else
    rm -rf "$@"
  fi
}

function noversion()
{
  echo "$1" | sed -e 's/-*\(\([0-9\.]\)*\([_-]rc\)*\(-pre\)*\([0-9][a-zA-Z]\)*\)*\(\.tar\..z2*\)$/\6/'
}

# output the sha1sum of a file
function sha1file()
{
  sha1sum "$@" | awk '{print $1}'
}

# Extract tarball named in $1 and apply all relevant patches into
# "$BUILD/sources/$1".  Record sha1sum of tarball and patch files in
# sha1-for-source.txt.  Re-extract if tarball or patches change.

function extract()
{
  SRCTREE="${BUILD}/sources"
  BASENAME="$(noversion "$1")"
  BASENAME="${BASENAME/%\.tar\.*/}"
  SHA1FILE="$(echo "${SRCTREE}/${BASENAME}/sha1-for-source.txt")"
  SHA1TAR="$(sha1file "${SRCDIR}/$1")"

  # Sanity check: don't ever "rm -rf /".  Just don't.

  if [ -z "$BASENAME" ] || [ -z "$SRCTREE" ]
  then
    dienow
  fi

  # If it's already extracted and up to date (including patches), do nothing.
  SHALIST=$(cat "$SHA1FILE" 2> /dev/null)
  if [ ! -z "$SHALIST" ]
  then
    for i in "$SHA1TAR" $(sha1file "${SOURCES}/patches/$BASENAME"* 2>/dev/null)
    do
      # Is this sha1 in the file?
      if [ -z "$(echo "$SHALIST" | sed -n "s/$i/$i/p" )" ]
      then
        SHALIST=missing
        break
      fi
      # Remove it
      SHALIST="$(echo "$SHALIST" | sed "s/$i//" )"
    done
    # If we matched all the sha1sums, nothing more to do.
    [ -z "$SHALIST" ] && return 0
  fi

  echo -n "Extracting '${BASENAME}'"
  # Delete the old tree (if any).  Create new empty working directories.
  rm -rf "${BUILD}/temp" "${SRCTREE}/${BASENAME}" 2>/dev/null
  mkdir -p "${BUILD}"/{temp,sources} || dienow

  # Is it a bzip2 or gzip tarball?
  DECOMPRESS=""
  [ "$1" != "${1/%\.tar\.bz2/}" ] && DECOMPRESS="j"
  [ "$1" != "${1/%\.tar\.gz/}" ] && DECOMPRESS="z"

  cd "${WORK}" &&
  { tar -xv${DECOMPRESS} -f "${SRCDIR}/$1" -C "${BUILD}/temp" || dienow
  } | dotprogress

  mv "${BUILD}/temp/"* "${SRCTREE}/${BASENAME}" &&
  rmdir "${BUILD}/temp" &&
  echo "$SHA1TAR" > "$SHA1FILE"

  [ $? -ne 0 ] && dienow

  # Apply any patches to this package

  ls "${SOURCES}/patches/$BASENAME"* 2> /dev/null | sort | while read i
  do
    if [ -f "$i" ]
    then
      echo "Applying $i"
      (cd "${SRCTREE}/${BASENAME}" && patch -p1 -i "$i") || dienow
      sha1file "$i" >> "$SHA1FILE"
    fi
  done
}

function download()
{
  FILENAME=`echo "$URL" | sed 's .*/  '`
  BASENAME=`noversion "$FILENAME"`

  # The extra "" is so we test the sha1sum after the last download.

  for i in "$URL" http://impactlinux.com/firmware/mirror/"$FILENAME" \
    http://landley.net/code/firmware/mirror/"$FILENAME" ""
  do
    # Return success if we have a valid copy of the file

    # Test first (so we don't re-download a file we've already got).

    SUM=`cat "$SRCDIR/$FILENAME" | sha1sum | awk '{print $1}'`
    if [ x"$SUM" == x"$SHA1" ] || [ -z "$SHA1" ] && [ -f "$SRCDIR/$FILENAME" ]
    then
      touch "$SRCDIR/$FILENAME"
      if [ -z "$SHA1" ]
      then
        echo "No SHA1 for $FILENAME ($SUM)"
      else
        echo "Confirmed $FILENAME"
      fi
      if [ ! -z "$EXTRACT_ALL" ]
      then
        extract "$FILENAME"
      fi
      return $?
    fi

    # If there's a corrupted file, delete it.  In theory it would be nice
    # to resume downloads, but wget creates "*.1" files instead.

    rm "$SRCDIR/$FILENAME" 2> /dev/null

    # If we have another source, try to download file.

    if [ -n "$i" ]
    then
      wget -t 2 -T 20 -P "$SRCDIR" "$i"
    fi
  done

  # Return failure.

  echo "Could not download $FILENAME"
  echo -en "\e[0m"
  return 1
}

# Clean obsolete files out of the source directory

START_TIME=`date +%s`

function cleanup_oldfiles()
{
  for i in "${SRCDIR}"/*
  do
    if [ -f "$i" ] && [ "$(date +%s -r "$i")" -lt "${START_TIME}" ]
    then
      echo Removing old file "$i"
      rm -rf "$i"
    fi
  done
}

function dienow()
{
  echo -e "\e[31mExiting due to errors\e[0m"
  exit 1
}

function dotprogress()
{
  x=0
  while read i
  do
    x=$[$x + 1]
    if [[ "$x" -eq 25 ]]
    then
      x=0
      echo -n .
    fi
  done
  echo
}

# Extract package $1, use out-of-tree build directory $2 (or $1 if no $2)
# Use symlink directory $3 (or $1 if no $3)

function setupfor()
{
  export WRAPPY_LOGPATH="$WRAPPY_LOGDIR/cmdlines.${STAGE_NAME}.setupfor"

  # Make sure the source is already extracted and up-to-date.
  cd "${SRCDIR}" &&
  extract "${1}-"*.tar* || exit 1

  # Set CURSRC

  export CURSRC="$1"
  [ ! -z "$3" ] && CURSRC="$3"
  CURSRC="${WORK}/${CURSRC}"

  # Announce package, with easy-to-grep-for "===" marker.

  echo "=== Building $1 ($ARCH_NAME)"
  echo "Snapshot '$1'..."
  cd "${WORK}" || dienow
  if [ $# -lt 3 ]
  then
    rm -rf "${CURSRC}" || dienow
  fi
  mkdir -p "${CURSRC}" &&
  cp -lfR "${SRCTREE}/$1/"* "${CURSRC}"

  [ $? -ne 0 ] && dienow

  # Do we have a separate working directory?

  if [ -z "$2" ]
  then
    cd "$1"* || dienow
  else
    mkdir -p "$2" &&
    cd "$2" || dienow
  fi
  export WRAPPY_LOGPATH="$WRAPPY_LOGDIR/cmdlines.${STAGE_NAME}.$1"
}
