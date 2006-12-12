#!/bin/sh

function download()
{
  FILENAME=`echo "$URL" | sed 's .*/  '`
  BASENAME=`echo "$FILENAME" | sed -r -e 's/-*([0-9\.]|-rc)*(\.tar\..z2*)$/\2/'`

  if [ ! -z "$STAGEDIR" ]
  then
    rm -f "$STAGEDIR/$BASENAME" 2> /dev/null
    ln -s "$FROMSRC/$FILENAME" "$STAGEDIR/$BASENAME"
  fi

  # The extra "" is so we test the sha1sum after the last download.

  for i in "$URL" http://www.landley.net/code/firmware/mirror/"$FILENAME" ""
  do
    # Return success if we have a valid copy of the file

    # Test first (so we don't re-download a file we've already got).

    SUM=`cat "$SRCDIR/$FILENAME" | sha1sum | awk '{print $1}'`
    if [ x"$SUM" == x"$SHA1" ]
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
  return 1
}

function dienow()
{
  echo "Exiting due to errors"
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
  FILE="${SOURCES}/${STAGE}/$1"
  if [ -f "${FILE}".tar.bz2 ]
  then
    FILE="${FILE}".tar.bz2
    DECOMPRESS="j"
  else
    FILE="${FILE}".tar.gz
    DECOMPRESS="z"
  fi
  echo "=== Building $1"
  echo -n "Extracting"
  cd "${WORK}" &&
  { tar xv${DECOMPRESS}f "$FILE" || dienow
  } | dotprogress
  if [ -z "$2" ]
  then
    cd "$1"* || dienow
  else
    mkdir "$2"
    cd "$2" || dienow
  fi
  export CURSRC="$1"
  [ ! -z "$3" ] && CURSRC="$3"
  export CURSRC=`echo "${WORK}/${CURSRC}"*`
  [ ! -d "${CURSRC}" ] && dienow
}

# Setup

umask 022
unset CFLAGS CXXFLAGS

# Find/create directories

TOP=`pwd`
export SOURCES="${TOP}/sources"
export SRCDIR="${SOURCES}/packages"
export WORK="${TOP}/build/temp"
export FROMSRC=../packages
export CROSS_BASE="${TOP}/build/cross-compiler"
mkdir -p "${SRCDIR}" "${WORK}"

# For bash: check the $PATH for new executables added after startup.
set +h

# Get target platform from first command line argument.

if [ -z "$NO_ARCH" ]
then
  ARCH="$(echo "$1" | sed 's@.*/@@')"
  if [ ! -f "${TOP}/sources/configs/${ARCH}" ]
  then
    echo "Usage: $0 ARCH"
    echo "Supported architectures: "
    (cd "${TOP}/sources/configs" && ls)
    exit 1
  fi

  # Which platform are we building for?

  export CROSS_HOST=`uname -m`-unknown-linux-gnu
  export CROSS_TARGET=${ARCH}-unknown-linux-gnu

  # Read the relevant config file.

  source "${TOP}/sources/configs/${ARCH}"

  # Add the cross compiler to the start of the path.

  export CROSS="${TOP}/build/cross-compiler-$ARCH"
  mkdir -p "${CROSS}" || dienow
  export PATH=${CROSS}/bin:"$PATH"
fi

[ -z "$CLEANUP" ] && CLEANUP="rm -rf"
