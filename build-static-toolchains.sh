#!/bin/bash

# This script builds static toolchains linked against uClibc.
# It boots a system image under qemu, copies the build into it, runs
# cross-compiler.sh for each target, and copies out the results.

# The first argument is the host to build for.  (Which system-image to run
# the build under.)

# Additional arguments are the targets to build for that host.  If no
# targets are specified, the script builds all of them.

if [ $# -eq 0 ]
then
  echo -e "Usage: build-static-toolchains.sh HOST_ARCH [TARGET_ARCH...]\n" >&2

  # Fall through to show supported architectures.
fi

source sources/include.sh || exit 1

# Grab host to build for.  (This is the system image we'll run under qemu.)

STATIC_HOST="$1"
shift
[ -z "$*" ] && STATIC_TARGETS="$(echo $(cd sources/targets; ls))" || STATIC_TARGETS="$@"

# Step 1, make sure the appropriate host files exist.

./download.sh --extract || dienow
if [ ! -f build/system-image-$STATIC_HOST.tar.bz2 ]
then
  ./build.sh $STATIC_HOST || dienow
fi

# Kill all the netcat instances if we exit prematurely

trap "kill 0" EXIT

function build_for_static_host()
{
  # Feed a script into qemu.  Pass data back and forth via netcat.
  # This intentionally _doesn't_ use $NICE, so the distcc master node is higher
  # priority than the distccd slave nodes.

  KERNEL_EXTRA="ro" ./run-from-build.sh "$STATIC_HOST" << EOF
          #
export USE_UNSTABLE=$USE_UNSTABLE
export NATIVE_RETROFIT_CXX=1
export CROSS_BUILD_STATIC=1
rm -rf /home/firmware
mkdir -p /home/firmware &&
cd /home/firmware &&
netcat 10.0.2.2 $(build/host/netcat -s 127.0.0.1 -l tar c *.sh sources build/sources) | tar xv 2>&1 | pipe_progress > /dev/null &&
mkdir -p build/logs || exit 1
for i in $STATIC_TARGETS
do
  ./cross-compiler.sh \$i && ./mini-native.sh \$i
done
(cd build; tar c cross-compiler-*.tar.bz2) | netcat 10.0.2.2 \
  $(mkdir -p build/static; cd build/static; ../host/netcat -s 127.0.0.1 -l tar xv)
exit
EOF
}

# If FORK, fork one qemu instance for each target

if [ ! -z "$FORK" ]
then
  for i in $STATIC_TARGETS
  do
    rm -f "${BUILD}/system-image-${STATIC_HOST}/hdb-${i}.img" 2>/dev/null
    (HDB="hdb-$i.img" STATIC_TARGETS="$i" build_for_static_host | tee out-static-$i.txt | grep ===) &
    rm -f "${BUILD}/system-image-${STATIC_HOST}/hdb-${i}.img" 2>/dev/null
  done

  wait4background 0
else
  build_for_static_host
fi

