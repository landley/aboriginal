#!/bin/bash

# Nightly snapshot build script.

# Wrapper can set:
#
# UPLOAD_TO=busybox.net:public_html/fwlnew
# USE_UNSTABLE=busybox,toybox,uClibc

[ -z "$NICE" ] && NICE="nice -n 20"

source sources/functions.sh

# Parse command line arguments

FORKCOUNT=0
while [ ! -z "$1" ]
do
  if [ "$1" == "--fork" ]
  then
    shift
    FORKCOUNT="$(echo $1 | | sed -n '/^[0-9]/{;s/[^0-9]//g;p;}')"
    [ ! -z "$FORKCOUNT" ] && shift || FORKCOUNT=0
  else
    echo "Unknown argument $1"
    dienow
  fi
done

SERVER="$(echo "$UPLOAD_TO" | sed 's/:.*//')"
SERVERDIR="$(echo "$UPLOAD_TO" | sed 's/[^:]*://')"

# Define functions

function build_this_target()
{
  if [ ! -e build/cross-compiler-$1/bin/$1-gcc ]
  then
    $NICE ./cross-compiler.sh $1 || return 1
  fi
  $NICE ./mini-native.sh $1 || return 1
  $NICE ./package-mini-native.sh $1 || return 1
}

function upload_stuff()
{
  [ -z "$SERVER" ] && return
  scp build/{cross-compiler,mini-native,system-image}-$1.tar.bz2 \
	build/buildlog-$1.txt.bz2 ${SERVER}:${SERVERDIR}
}

function build_and_log()
{
  { build_this_target $1 2>&1 || return 1
  } | tee out-$1.txt
}

function build_log_upload()
{
  build_and_log | tee >(bzip2 > build/buildlog-$1.txt.bz2)

  if [ -z "$2" ]
  then
    upload_stuff "$1"
  else
    upload_stuff "$1" >/dev/null &
  fi
}

# Clean up old builds, fetch fresh packages.

(hg pull -u; ./download.sh || dienow) &
rm -rf build out-*.txt &
wait4background 0

# Build host tools, extract packages (not asynchronous).

($NICE ./host-tools.sh && $NICE ./download.sh --extract || dienow) | tee out.txt

# Create and upload readme (in background)

do_readme | tee build/README.txt | \
  ( [ -z "$SERVER" ] && \
    cat || ssh ${SERVER} "cd ${SERVERDIR}; cat > README.txt"
  ) &

# Build each architecture

for i in $(cd sources/targets; ls);
do
  if [ ! -z "$FORKCOUNT" ]
  then
    echo Launching $i
    if [ "$FORKCOUNT" -eq 1 ]
    then
      build_log_upload "$i" "1" || dienow
    else
      (build_log_upload $i 2>&1 </dev/null | grep "^==="; echo Completed $i ) &
      [ "$FORKCOUNT" -gt 0 ] && wait4background $[${FORKCOUNT}-1] "ssh "
    fi
  else
    build_log_upload $i || dienow
  fi
done

# Wait for ssh/scp invocations to finish.

echo Waiting for background tasks...

wait4background 0
