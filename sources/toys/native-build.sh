#!/bin/bash

# Launch a system image in the emulator with a control image to drive an
# automated native build, plus an FTP server on the host to upload results to.

# If you already have an FTP server, export FTP_SERVER and/or FTP_PORT.

# Parse arguments

if [ $# -ne 1 ]
then
  echo "usage: $0 CONTROL_IMAGE" >&2
  exit 1
fi

if [ ! -f "$1" ]
then
  echo "Filesystem image $1 missing" >&2
  exit 1
fi
HDCFILE="$(readlink -f $1)"

TOP="$(pwd)"

# If we're running from the build directory, add build/host and cross compiler
# to the path.

[ -d ../host ] &&
  PATH="$TOP/../host:$TOP/../cross-compiler-$1/bin:$TOP/../simple-cross-compiler-$1/bin:$PATH"

INCLUDE unique-port.sh

# Do we already have an FTP daemon?

if [ -z "$FTP_SERVER" ]
then
  FTP_SERVER=127.0.0.1
elif [ -z "$FTP_PORT" ]
then
  FTP_PORT=21
fi

if [ -z "$FTP_PORT" ]
then
  if [ -z "$(which busybox)" ]
  then
    echo "Warning: can't find busybox, no ftp daemon launched." >&2
  else
    FTP_PORT=$(unique_port)

    echo === launching FTP daemon on port "$FTP_PORT"

    # Fire off an ftp daemon, making sure it's killed when this script exits.
    # (We use the busybox version because no two ftp daemons have quite the same
    # command line arguments, and this one's a known quantity.)

    mkdir -p upload
    # Busybox needs -s 127.0.0.1 support here
    busybox nc -p $FTP_PORT -lle busybox ftpd -w upload &
    trap "kill $(jobs -p)" EXIT
    disown $(jobs -p)

    # QEMU's alias for host loopback

    FTP_SERVER=10.0.2.2
  fi
fi

# Run emulator as a child process, feeding in -hdc and some extra environment
# variables so it auto-launches the build process.

rm -f hdb.img
HDC="$HDCFILE" KERNEL_EXTRA="FTP_SERVER=$FTP_SERVER FTP_PORT=$FTP_PORT" \
  ./dev-environment.sh

echo === End native build
