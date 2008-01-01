#!/bin/bash

# Strip the version number off a tarball

function noversion()
{
  echo "$1" | sed -e 's/-*\([0-9\.]|[_-]rc|-pre|[0-9][a-zA-Z]\)*\(\.tar\..z2*\)$/\2/'
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
  BASENAME=`noversion "$1"`
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

  for i in "$URL" http://www.landley.net/code/firmware/mirror/"$FILENAME" ""
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
      wget -P "$SRCDIR" "$i"
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
  cd "${WORK}" &&
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
}

# Setup

umask 022
unset CFLAGS CXXFLAGS
# This tells gcc to aggressively garbage collect its internal data
# structures.  Without this, gcc triggers the OOM killer trying to rebuild
# itself in 128 megs of ram, which is the QEMU default size.
[ "$(uname -m)" != "x86_64" ] &&
export CFLAGS="--param ggc-min-expand=0 --param ggc-min-heapsize=8192"

# Find/create directories

TOP=`pwd`
export SOURCES="${TOP}/sources"
export SRCDIR="${SOURCES}/packages"
export FROMSRC=../packages
export BUILD="${TOP}/build"
export HOSTTOOLS="${BUILD}/host"
export WORK="${BUILD}/host-temp"
export PATH="${HOSTTOOLS}:$PATH"
mkdir -p "${SRCDIR}"

# For bash: check the $PATH for new executables added after startup.
set +h

# Are we doing a short build?

if [ "$1" == "--short" ]
then
  export BUILD_SHORT=1
  shift
fi

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
  rm -rf "${WORK}"
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
  export IMAGE="${BUILD}/image-${ARCH}.ext2"


  emulator_command image-$ARCH.ext2 zImage-$ARCH \
    "rw init=/tools/bin/sh panic=1 PATH=/tools/bin" > "$BUILD/run-$ARCH.sh" &&
  chmod +x "$BUILD/run-$ARCH.sh"
fi
mkdir -p "${WORK}"

[ -z "$CLEANUP" ] && CLEANUP="rm -rf"
[ -z "$CC" ] && CC=gcc
if [ -z "$CPUS" ]
then
  export CPUS=$[$(echo /sys/devices/system/cpu/cpu[0-9]* | wc -w)+0]
  [ "$CPUS" -lt 1 ] && CPUS=1
fi
