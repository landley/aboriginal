#!/bin/bash

# Launch a system image under the emulator and natively build static versions
# of a few packages.

# Takes the name of the architecture to build for as its first argument,
# with no arguments builds all architectures in build/system-image-*
# (If $FORK is set, run them in parallel.)

. sources/functions.sh || exit 1

STAGE_DIR="$(pwd)/build/cron-temp"

# Create an hdc image with the source code and build script

sources/more/setup-native-static-build.sh "$STAGE_DIR"

# Fire off the ftp daemon, making sure it's killed when this script exits

build/host/netcat -s 127.0.0.1 -p 9876 -L build/host/ftpd -w "$STAGE_DIR" &
trap "kill $(jobs -p)" EXIT
disown $(jobs -p)

find build -name "hdb.img" | xargs rm

# Run emulator as a child process, feeding in -hdc and some extra environment
# variables so it auto-launches the build process.

function do_arch()
{
  set_titlebar "Native build for $1"
  HDC="$STAGE_DIR/hdc.sqf" KERNEL_EXTRA="OUTPORT=9876 ARCH=$1" \
  sources/timeout.sh 60 ./run-from-build.sh $1
}

# If we have a command line argument, build just that arch, otherwise build
# all arches that managed to create a system image.

if [ ! -z "$1" ]
then
  do_arch "$1"
else
  mkdir -p build/logs

  for i in $(ls build/system-image-*.tar.bz2 | sed 's@build/system-image-\(.*\)\.tar\.bz2@\1@' | grep -v system-image-hw-)
  do
    maybe_fork "do_arch $i | tee build/log/native-static-$i.txt | maybe_quiet"
  done

  wait
fi

echo End of native build
