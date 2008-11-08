#!/bin/bash

# Nightly snapshot build script.

# Wrapper can set:
#
# UPLOAD_TO=busybox.net:public_html/fwlnew
# UNSTABLE=busybox,toybox,uClibc

[ -z "$NICE" ] && NICE="nice -n 20"

source sources/functions.sh

function get_download_version()
{
  getversion $(sed -n 's@URL=.*/\(.[^ ]*\).*@\1@p' download.sh | grep ${1}-)
}

function identify_release()
{
  if [ -d build/sources/alt-$1/.svn ]
  then
    echo subversion rev \
      $(svn info build/sources/alt-uClibc | sed -n "s/^Revision: //p")
  elif [ -d build/sources/alt-$1/.hg ]
  then
    echo mercurial rev \
      $(hg tip | sed -n 's/changeset: *\([0-9]*\).*/\1/p')
  else
    echo release version $(get_download_version $1)
  fi
}

function do_readme()
{
  # Grab FWL version number

  cat << EOF
Built on $(date +%F) from:

  Build script:
    Firmware Linux (http://landley.net/code/firmware) mercurial rev $(hg tip | sed -n 's/changeset: *\([0-9]*\).*/\1/p')

  Base packages:
    uClibc (http://uclibc.org) $(identify_release uClibc)
    BusyBox (http://busybox.net) $(identify_release busybox)
    Linux (http://kernel.org/pub/linux/kernel) $(identify_release linux)

  Toolchain packages:
    Binutils (http://www.gnu.org/software/binutils/) $(identify_release binutils)
    GCC (http://gcc.gnu.org) $(identify_release gcc-core)
    gmake (http://www.gnu.org/software/make) $(identify_release make)
    bash (ftp://ftp.gnu.org/gnu/bash) $(identify_release bash)

  Optional packages:
    Toybox (http://landley.net/code/toybox) $(identify_release toybox)
    distcc (http://distcc.samba.org) $(identify_release distcc)
    uClibc++ (http://cxx.uclibc.org) $(identify_release uClibc++)
EOF
}

function build_this_target()
{
  $NICE ./cross-compiler.sh $1 || return 1
  $NICE ./mini-native.sh $1 || return 1
  $NICE ./package-mini-native.sh $1 || return 1
}

function upload_stuff()
{
  [ -z "$SERVER" ] && return
  scp build/{cross-compiler,mini-native,system-image}-$1.tar.bz2 \
	build/buildlog-$1.txt.bz2 ${SERVER}:${SERVERDIR}
}

function build_log_upload()
{
  { build_this_target $1 2>&1 || return 1
  } | tee out-$1.txt | tee >(bzip2 > build/buildlog-$1.txt.bz2)

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

# Build host tools, extract packages. 

($NICE ./host-tools.sh && $NICE ./download.sh --extract || dienow) | tee out.txt

SERVER="$(echo "$UPLOAD_TO" | sed 's/:.*//')"
SERVERDIR="$(echo "$UPLOAD_TO" | sed 's/[^:]*://')"

do_readme | tee build/README.txt | \
  ( [ -z "$SERVER" ] && \
    cat || ssh ${SERVER} "cd ${SERVERDIR}; cat > README.txt"
  ) &

for i in $(cd sources/targets; ls);
do
  if [ "$1" == "--fork" ]
  then
    echo Launching $i
    if [ "$2" == "1" ]
    then
      build_log_upload "$i" "1" || dienow
    else
      (build_log_upload $i 2>&1 </dev/null | grep "^==="; echo Completed $i ) &
      [ ! -z "$2" ] && wait4background $[${2}-1] "ssh "
    fi
  else
    build_log_upload $i || dienow
  fi
done

# Wait for ssh/scp invocations to finish.

wait4background 0
