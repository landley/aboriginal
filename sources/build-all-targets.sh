#!/bin/bash

# Nightly snapshot build script.

# TODO:
#
# Wrapper must set:
# SERVER=busybox.net
# SERVERDIR=public_html/fwlnew
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

  Packages:
    uClibc (http://uclibc.org) $(identify_release uClibc)
    BusyBox (http://busybox.net) $(identify_release busybox)
    Linux (http://kernel.org/pub/linux/kernel) $(identify_release linux)
    Binutils (http://www.gnu.org/software/binutils/) $(identify_release binutils)
    GCC (http://gcc.gnu.org) $(identify_release gcc-core)
    gmake (http://www.gnu.org/software/make) $(identify_release make)
    Toybox (http://landley.net/code/toybox) $(identify_release toybox)

EOF
}

function build_this_target()
{
  ./cross-compiler.sh $i || return
  [ ! -z "$SERVER" ] &&
    scp build/cross-compiler-$i.tar.bz2 ${SERVER}:${SERVERDIR} >/dev/null &
  ./mini-native.sh $i || return
  [ ! -z "$SERVER" ] &&
    scp build/mini-native-$i.tar.bz2 ${SERVER}:${SERVERDIR} >/dev/null &
  ./package-mini-native.sh $i || return
  [ ! -z "$SERVER" ] &&
    scp build/system-image-$i.tar.bz2 ${SERVER}:${SERVERDIR} >/dev/null &
}

# Clean up old builds

hg pull -u &
rm -rf build out-*.txt &
wait4background 0

# Fetch fresh packages, build host tools, extract packages. 

(./download.sh &&
 ./host-tools.sh &&
 ./download.sh --extract || dienow) | tee out.txt

do_readme | tee build/README.txt | ( [ -z "$SERVER" ] && cat || ssh ${SERVER} "cd ${SERVERDIR}; cat > README.txt" ) &

for i in $(cd sources/targets; ls);
do
  build_this_target 2>&1 | tee out-$i.txt
  [ ! -z "$SERVER" ] && (cat out-$i | bzip2 | ssh ${SERVER} \
    "cat > ${SERVERDIR}/buildlog-$(echo $i | sed 's/^out-//').bz2") &
done

# Wait for ssh/scp invocations to finish.

wait4background 0
