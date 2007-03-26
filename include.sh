#!/bin/sh

temp=`ls -l /bin/sh | sed 's/.*-> //'`
if [ "$temp" == "dash" ]
then
  echo "Error: your /bin/sh points to dash."
  exit 1
fi

function download()
{
  FILENAME=`echo "$URL" | sed 's .*/  '`
  BASENAME=`echo "$FILENAME" | sed -r -e 's/-*([0-9\.]|-rc|[0-9][a-zA-Z])*(\.tar\..z2*)$/\2/'`

  if [ ! -z "$LINKDIR" ]
  then
    rm -f "$LINKDIR/$BASENAME" 2> /dev/null
    ln -s "$FROMSRC/$FILENAME" "$LINKDIR/$BASENAME"
  fi

  # The extra "" is so we test the sha1sum after the last download.

  for i in "$URL" http://www.landley.net/code/firmware/mirror/"$FILENAME" \
           http://engineering.timesys.com/~landley/mirror/"$FILENAME" ""
  do
    # Return success if we have a valid copy of the file

    # Test first (so we don't re-download a file we've already got).

    SUM=`cat "$SRCDIR/$FILENAME" | sha1sum | awk '{print $1}'`
    if [ -z "$SHA1" ] && [ -f "$SRCDIR/$FILENAME" ]
    then
      touch "$SRCDIR/$FILENAME"
      echo "No SHA1 for $FILENAME"
      return 0
    elif [ x"$SUM" == x"$SHA1" ]
    then
      touch "$SRCDIR/$FILENAME"
      echo "Confirmed $FILENAME"
      return 0
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

# Extract package $1, use work directory $2 (or $1 if no $2), use source
# directory $3 (or $1 if no $3)

function setupfor()
{
  # Is it a bzip2 or gzip tarball?

  FILE="${LINKDIR}/$1"
  if [ -f "${FILE}".tar.bz2 ]
  then
    FILE="${FILE}".tar.bz2
    DECOMPRESS="j"
  else
    FILE="${FILE}".tar.gz
    DECOMPRESS="z"
  fi

  # Announce package, with easy-to-grep-for "===" marker.  Extract it.

  echo "=== Building $1 ($ARCH_NAME)"
  echo -n "Extracting"
  cd "${WORK}" &&
  { tar xv${DECOMPRESS}f "$FILE" || dienow
  } | dotprogress

  # Do we have a separate working directory?

  if [ -z "$2" ]
  then
    cd "$1"* || dienow
  else
    mkdir -p "$2" &&
    cd "$2" || dienow
  fi

  # Set CURSRC

  export CURSRC="$1"
  [ ! -z "$3" ] && CURSRC="$3"
  export CURSRC=`echo "${WORK}/${CURSRC}"*`
  [ ! -d "${CURSRC}" ] && dienow

  # Apply any patches to this package

  for i in "${SOURCES}/patches/$1"*
  do
    if [ -f "$i" ]
    then
      (cd "${CURSRC}" && patch -p1 -i "$i") || dienow
    fi
  done
}

# Setup

umask 022
unset CFLAGS CXXFLAGS
export CFLAGS="--param ggc-min-expand=0 --param ggc-min-heapsize=8192"

# Find/create directories

TOP=`pwd`
export SOURCES="${TOP}/sources"
export SRCDIR="${SOURCES}/packages"
export FROMSRC=../packages
export LINKDIR="${SOURCES}/build-links"
export BUILD="${TOP}/build"
export HOSTTOOLS="${BUILD}/host"
export WORK="${BUILD}/host-temp"
export PATH="${HOSTTOOLS}:$PATH"
mkdir -p "${SRCDIR}" "${LINKDIR}"

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
  export CROSS_HOST=`uname -m`-walrus-linux
  [ -z "$CROSS_TARGET" ] && CROSS_TARGET=${ARCH}-unknown-linux
  export CROSS_TARGET

  # Read the relevant config file.

  source "${TOP}/sources/configs/${ARCH}"

  # Setup directories and add the cross compiler to the start of the path.

  export CROSS="${BUILD}/cross-compiler-$ARCH"
  export NATIVE="${BUILD}/mini-native-$ARCH"
  export PATH="${CROSS}/bin:${HOSTTOOLS}:$PATH"
  export IMAGE="${BUILD}/image-${ARCH}.ext2"
fi
mkdir -p "${WORK}"

[ -z "$CLEANUP" ] && CLEANUP="rm -rf"
[ -z "$CC" ] && CC=gcc
