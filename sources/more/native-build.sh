#!/bin/bash

# setup hdc.sqf
# find build -name "hdb.img" | xargs rm

# Launch a system image under the emulator under the control of a filesystem
# image, with an FTP server to upload results to.

. sources/functions.sh || exit 1

# Parse arguments

if [ $# -lt 3 ]
then
  echo "usage: $0 ARCH HDCFILE OUTPUTDIR [TIMEOUT_SECONDS]" >&2
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

[ ! -z "$4" ] && DO_TIMEOUT="sources/timeout.sh $4"

# Fire off the ftp daemon, making sure it's killed when this script exits

. sources/toys/unique-port.sh || exit 1
PORT=$(unique_port)
build/host/netcat -s 127.0.0.1 -p $PORT -L build/host/ftpd -w "$STAGE_DIR" &
trap "kill $(jobs -p)" EXIT
disown $(jobs -p)

# Run emulator as a child process, feeding in -hdc and some extra environment
# variables so it auto-launches the build process.

echo === Begin native build for $ARCH

rm -f sources/system-image-"$ARCH"/hdb.img
HDC="$HDCFILE" KERNEL_EXTRA="OUTPORT=$PORT ARCH=$ARCH" \
   $DO_TIMEOUT ./run-from-build.sh "$ARCH"

echo === End native build for $ARCH
