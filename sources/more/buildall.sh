#!/bin/bash

# Build every target architecture, creating out-$ARCH.txt log files.
# If $FORK is set, build them in parallel.

. sources/functions.sh || exit 1

[ -z "$STATIC_CROSS_COMPILER_HOST" ] && export STATIC_CROSS_COMPILER_HOST=i686
export BUILD_STATIC_NATIVE_COMPILER=1
export FAIL_QUIET=1

[ -z "${ARCHES}" ] &&
  ARCHES="$(cd sources/targets/; ls | grep -v '^hw-')"

[ -z "$HWARCHES" ] &&
  HWARCHES="$(cd sources/targets; ls | grep '^hw-')"

[ ! -z "$FORK" ] && QUIET=1

trap "killtree $$" EXIT

# Build the host architecture.  This has to be built first so the other
# architectures can canadian cross static compilers to run on the host using
# this toolchain to link against a host version of uClibc.

# This also performs the download.sh and host-tools.sh steps, which don't
# parallelize well if many build.sh instances try to call them at once.

# If this fails, don't bother trying to build the other targets.

blank_tempdir build
mkdir -p build/logs &&
ln -s out-"$STATIC_CROSS_COMPILER_HOST".txt build/logs/out-host.txt &&
(./build.sh 2>&1 "$STATIC_CROSS_COMPILER_HOST" || dienow) \
  | tee build/logs/build-"$STATIC_CROSS_COMPILER_HOST".txt | maybe_quiet

# Build all the remaining cross compilers, possibly in parallel

for i in ${ARCHES} ${HWARCHES}
do
  [ "$i" != "$STATIC_CROSS_COMPILER_HOST" ] &&
    maybe_fork "./build.sh $i 2>&1 | tee build/logs/build-${i}.txt | maybe_quiet"
done

wait

# Run smoketest.sh for each non-hw target.

for i in ${ARCHES}
do
  maybe_fork "sources/more/smoketest.sh $i 2>&1 | tee build/logs/smoketest-$i.txt | maybe_quiet"
done

wait

./smoketest-all.sh --logs
