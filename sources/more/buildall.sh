#!/bin/bash

# Build every target architecture, creating build-$ARCH.txt log files.
# If $FORK is set, build them in parallel.

. sources/functions.sh || exit 1

[ -z "$STATIC_CC_HOST" ] && export STATIC_CC_HOST=i686
export FAIL_QUIET=1

if [ -z "$*" ]
then
  [ -z "${ARCHES}" ] &&
    ARCHES="$(cd sources/targets/; ls | grep -v '^hw-')"

  [ -z "$HWARCHES" ] &&
    HWARCHES="$(cd sources/targets; ls | grep '^hw-')"
else
  ARCHES="$*"
fi

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
(EXTRACT_ALL=1 ./download.sh 2>&1 &&
 ./host-tools.sh 2>&1 &&
 ./simple-cross-compiler.sh 2>&1 "$STATIC_CC_HOST" ||
 dienow) | tee build/logs/build-host-cc.txt | maybe_quiet

cp packages/MANIFEST build || dienow

# Build all non-hw targets, possibly in parallel

for i in ${ARCHES}
do
  maybe_fork "./build.sh $i 2>&1 | tee build/logs/build-${i}.txt | maybe_quiet"
done

wait

# Build all hw targets, possibly in parallel

for i in ${HWARCHES}
do
  maybe_fork "./build.sh $i 2>&1 | tee build/logs/build-${i}.txt | maybe_quiet"
done

# Run smoketest.sh for each non-hw target.

for i in ${ARCHES}
do
  maybe_fork "./smoketest.sh $i 2>&1 | tee build/logs/smoketest-$i.txt | maybe_quiet"
done

wait

# Build dropbear and strace

sources/native-builds/static-tools.sh build/host-temp/hdc.sqf &&
mkdir -p build/native-static &&
for i in ${ARCHES}
do
  maybe_fork "sources/more/timeout.sh 60 sources/more/native-build.sh $i build/host-temp/hdc.sqf build/native-static | tee build/logs/native-$i.txt | maybe_quiet"
done

wait

# Create a file containing simple pass/fail results for all architectures.

sources/more/smoketest-all.sh --logs | tee build/logs/status.txt


