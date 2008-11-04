#!/bin/bash

# Nightly snapshot build script.

# TODO:
#
# Wrapper must set:
# UPLOAD_TO=busybox.net:public_html/fwlnew
# UNSTABLE=busybox,toybox,uClibc

source sources/functions.sh

function get_download_version()
{
  getversion $(sed -n 's@URL=.*/\(.[^ ]*\).*@\1@p' download.sh | grep ${1}-)
}

function identify_release()
{
  if [ -d build/sources/alt-$1/.svn ]
  then
    echo subversion changeset $(svn info build/sources/alt-uClibc | sed -n "s/^Revision: //p")
  elif [ -d build/sources/alt-$1/.hg ]
  then
    echo mercurial changeset $(hg tip | sed -n 's/changeset: *\([0-9]*\).*/\1/p')
  else
    echo release version $(get_download_version $1)
  fi
}

function do_readme()
{
  # Grab FWL version number

  FWL_REV="$(hg tip | sed -n 's/changeset: *\([0-9]*\).*/\1/p')"

  cat << EOF
Built on $(date +%F) from:

  Build script:
    Firmware Linux (http://landley.net/code/firmware) mercurial changeset $FWL_REV

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
  ./cross-compiler.sh $1 || dienow
  [ ! -z "$SERVER" ] &&
    scp build/cross-compiler-$1.tar.bz2 ${SERVER}:${SERVERDIR} >/dev/null &
  ./mini-native.sh $1 || dienow
  [ ! -z "$SERVER" ] &&
    scp build/mini-native-$1.tar.bz2 ${SERVER}:${SERVERDIR} >/dev/null &
  ./package-mini-native.sh $1 || dienonw
  [ ! -z "$SERVER" ] &&
    scp build/system-image-$1.tar.bz2 ${SERVER}:${SERVERDIR} >/dev/null &
}

function build_log_upload()
{
  build_this_target $1 2>&1 | tee out-$1.txt
  [ ! -z "$SERVER" ] && (cat out-$1 | bzip2 | ssh ${SERVER} \
    "cat > ${SERVERDIR}/buildlog-$(echo $1 | sed 's/^out-//').bz2") &
}

# Clean up old builds, fesh fresh packages.

(hg pull -u; ./download.sh || dienow) &
rm -rf build out-*.txt &
wait4background 0

# Build host tools, extract packages. 

(./host-tools.sh && ./download.sh --extract || dienow) | tee out.txt

SERVER="$(echo "$UPLOAD_TO" | sed 's/:.*//')"
SERVERDIR="$(echo "$UPLOAD_TO" | sed 's/[^:]*://')"

do_readme | tee build/README.txt | ( [ -z "$SERVER" ] && cat || ssh ${SERVER} "cd ${SERVERDIR}; cat > README.txt" ) &

for i in $(cd sources/targets; ls);
do
  if [ "$1" == "--fork" ]
  then
    echo Launching $i
    (build_log_upload $i 2>&1 </dev/null | grep ===) &
    [ ! -z "$2" ] && wait4background $[${2}-1]
  else
    build_log_upload $i
  fi
done

# Wait for ssh/scp invocations to finish.

wait4background 0
