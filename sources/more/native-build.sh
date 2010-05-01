#!/bin/bash

# Launch a system image under the emulator under the control of a filesystem
# image, with an FTP server to upload results to.

# Parse arguments

if [ $# -ne 3 ]
then
  echo "usage: $0 ARCH HDCFILE OUTPUTDIR" >&2
  exit 1
fi

ARCH="$1"
if [ ! -f "$2" ]
then
  echo "Filesystem image $2 missing" >&2
  exit 1
fi
HDCFILE="$(readlink -f $2)"
mkdir -p "$3" || dienow
STAGE_DIR="$(readlink -f $3)"

TOP="$(pwd)"

# If running from the source directory, add build/host and cross compiler
# to the path.

[ -d build/host ] &&
  PATH="$TOP/build/host:$TOP/build/cross-compiler-$1/bin:$TOP/build/simple-cross-compiler-$1/bin:$PATH"

if [ -z "$(which busybox)" ]
then
  echo "Warning: can't find busybox, no ftp daemon launched." >&2
else

  # Fire off an ftp daemon, making sure it's killed when this script exits.
  # (We use the busybox version because no two ftp daemons have quite the same
  # command line arguments, and this one's a known quantity.)

  . sources/toys/unique-port.sh 2>/dev/null &&
    FTP_PORT=$(unique_port) ||
    FTP_PORT=12345+$$

  # Replace toybox with busybox once -L is supported.

  toybox nc -s 127.0.0.1 -p $FTP_PORT -L busybox ftpd -w "$STAGE_DIR" &
  trap "kill $(jobs -p)" EXIT
  disown $(jobs -p)
fi

# Run emulator as a child process, feeding in -hdc and some extra environment
# variables so it auto-launches the build process.

echo === Begin native build for $ARCH

rm -f sources/system-image-"$ARCH"/hdb.img
HDC="$HDCFILE" KERNEL_EXTRA="OUTPORT=$FTP_PORT ARCH=$ARCH" \
   $DO_TIMEOUT ./run-from-build.sh "$ARCH"

echo === End native build for $ARCH
