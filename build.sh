#!/bin/sh

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

function setupfor()
{
  echo "=== Building $1"
  echo -n "Extracting"
  cd "${WORK}" &&
  tar xvjf "${SOURCES}/${STAGE}/$1".tar.bz2 | dotprogress
  cd "$1"* || dienow
}

# Setup

umask 022
unset CFLAGS CXXFLAGS

ARCH=x86_64

# Find/create directories

TOP=`pwd`
export CROSS="${TOP}/build/cross-compiler"
export WORK="${TOP}/build/temp"
export SOURCES="${TOP}/sources"
mkdir -p "${CROSS}" "${WORK}"

[ $? -ne 0 ] && dienow

# For bash: check the $PATH for new executables added after startup.
set +h
# Put the cross compiler in the path
export PATH=`pwd`/cross:/bin:/usr/bin

# Which platform are we building for?

[ "$ARCH" == x86_64 ] && export BUILD64="-m64"
export LFS_HOST=i686-pc-linux-gnu
export LFS_TARGET=${ARCH}-unknown-linux-gnu

export STAGE=build-cross

echo === Install linux-headers.

setupfor linux-headers
#cd "${WORK}"
#tar xvjf "${SOURCES}"/build-cross/linux-headers.tar.bz2 &&
#cd linux-headers* &&
mkdir "${CROSS}"/include &&
mv include/asm-${ARCH} "${CROSS}"/include/asm &&
mv include/asm-generic "${CROSS}"/include &&
mv include/linux "${CROSS}"/include &&
cd ..
rm -rf linux-headers*

[ $? -ne 0 ] && dienow

setupfor binutils
/bin/sh
