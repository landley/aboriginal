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

# run-from-build.sh needs things that aren't in build/host,
# such as qemu and fsck.ext2
PATH="$OLDPATH"

STATIC_HOST="$1"
shift
[ -z "$@" ] && STATIC_TARGETS="$(echo $(cd sources/targets; ls))" || STATIC_TARGETS="$@"

# Step 1, make sure the appropriate host files exist.

./download.sh --extract || dienow
if [ ! -f build/system-image-$STATIC_HOST.tar.bz2 ]
then
  ./build.sh $STATIC_HOST || dienow
fi

# Kill all the netcat instances if we exit prematurely

trap "kill 0" EXIT

# Feed a script into qemu.  Pass data back and forth via netcat.
# This intentionally _doesn't_ use $NICE, so the distcc master node is higher
# priority than the distccd slave nodes.

./run-from-build.sh "$STATIC_HOST" << EOF
          #
export USE_UNSTABLE=$USE_UNSTABLE
export CROSS_BUILD_STATIC=1
rm -rf /home/firmware
mkdir -p /home/firmware &&
cd /home/firmware &&
netcat 10.0.2.2 $(build/host/netcat -s 127.0.0.1 -l tar c *.sh sources packages build/sources) | tar xv 2>&1 | pipe_progress > /dev/null &&
mkdir -p build/logs || exit 1
for i in $STATIC_TARGETS
do
  ./cross-compiler.sh \$i | tee out-static-\$i.txt
done
tar c out-*.txt build/cross-compiler-*.tar.bz2 | netcat 10.0.2.2 \
  $(mkdir -p build/static; cd build/static; ../host/netcat -s 127.0.0.1 -l tar xv)
exit
EOF
