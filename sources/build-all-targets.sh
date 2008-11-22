#!/bin/bash

# Nightly snapshot build script.

# Wrapper can set:
# USE_UNSTABLE=busybox,toybox,uClibc
# USE_STATIC_HOST=i686

[ -z "$NICE" ] && NICE="nice -n 20"

source sources/functions.sh

# Parse command line arguments

FORKCOUNT=1
while [ ! -z "$1" ]
do
  if [ "$1" == "--fork" ]
  then
    shift
    FORKCOUNT="$(echo $1 | sed -n '/^[0-9]/{;s/[^0-9]//g;p;}')"
    [ ! -z "$FORKCOUNT" ] && shift || FORKCOUNT=0
  else
    echo "Unknown argument $1"
    dienow
  fi
done

# Define functions

function build_this_target()
{
  if [ ! -e build/cross-compiler-$1/bin/$1-gcc ]
  then
    $NICE ./cross-compiler.sh $1 &&
    ln build/cross-compiler-$1.tar.bz2 buildall || return 1
  fi

  $NICE ./mini-native.sh $1 &&
  ln build/mini-native-$1.tar.bz2 buildall || return 1

  $NICE ./package-mini-native.sh $1 &&
  ln build/system-image-$1.tar.bz2 buildall || return 1
}

function build_and_log()
{
  { build_this_target $ARCH 2>&1 || return 1
  } | tee >(bzip2 > buildall/logs/$1-$ARCH.txt.bz2)
}

# Iterate through architectures, either sequentially or in parallel.
# Run "$1 $ARCH", in parallel if necessary.

function for_each_arch()
{
  for ARCH in $(cd sources/targets; ls);
  do
    echo Launching $ARCH
    if [ "$FORKCOUNT" -eq 1 ]
    then
      "$@" "$ARCH" || dienow
    else
      ("$@" $ARCH 2>&1 </dev/null |
       grep "^==="; echo Completed $i ) &
      [ "$FORKCOUNT" -gt 0 ] && wait4background $[${FORKCOUNT}-1] "ssh "
    fi
  done

  wait4background 0
}

# Clean up old builds, fetch fresh packages.

rm -rf build/host
(hg pull -u; ./download.sh || dienow) &
rm -rf build buildall &
wait4background 0

mkdir -p buildall/logs || dienow

# Build host tools, extract packages (not asynchronous).

($NICE ./host-tools.sh && $NICE ./download.sh --extract || dienow) |
  tee >(bzip2 > buildall/logs/host-tools.txt.bz2)

# Create and upload readme (requires build/sources to be extracted)

do_readme | tee buildall/README.txt &

# If we need to create static cross compilers, build a version of mini-native
# to act as the host system.  (That way they're statically linked against
# uClibc, not whatever the host's library is.)

if [ ! -z "$USE_STATIC_HOST" ]
then
  ($NICE ./build.sh "$USE_STATIC_HOST" || dienow) |
    tee >(bzip2 > buildall/logs/static-host-$USE_STATIC_HOST.txt.bz2)

# Feed a script into qemu.  Pass data back and forth via netcat.
# This intentionally _doesn't_ use $NICE, so the distcc master node is higher
# priority than the distccd slave nodes.

./emulator-build.sh "$USE_STATIC_HOST" << EOF
          #
export USE_UNSTABLE=$USE_UNSTABLE
export CROSS_BUILD_STATIC=1
cd /home &&
netcat 10.0.2.2 $(build/host/netcat -s 127.0.0.1 -l hg archive -t tgz -) | tar xvz &&
cd firmware-* &&
netcat 10.0.2.2 $(build/host/netcat -s 127.0.0.1 -l tar c sources/packages) | tar xv &&
./download.sh --extract &&
mkdir -p build/logs || exit 1

for i in \$(cd sources/targets; ls)
do
  ./cross-compiler.sh \$i | tee build/logs/cross-static-\$i.txt
  bzip2 build/logs/cross-static-\$i.txt
done
cd build
tar c logs/* cross-compiler-*.tar.bz2 | netcat 10.0.2.2 \
  $(cd buildall; ../build/host/netcat -s 127.0.0.1 -l tar xv)
sync
exit
EOF

  # Extract the cross compilers

  for i in buildall/cross-compiler-*.tar.bz2
  do
    echo Extracting $i
    tar -xj -f $i -C build || dienow
  done
fi

# Build each architecture

for_each_arch build_and_log native
