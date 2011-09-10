#!/bin/bash

# Build every target architecture, saving log files to build/log.
# If $FORK is set, build them in parallel.

. sources/utility_functions.sh || exit 1

[ -z "$CROSS_COMPILER_HOST" ] && export CROSS_COMPILER_HOST=i686

trap "killtree $$" EXIT

# Build the host architecture.  This has to be built first so the other
# architectures can canadian cross static compilers to run on the host using
# this toolchain to link against a host version of uClibc.

# This also performs the download.sh and host-tools.sh steps, which don't
# parallelize well if many build.sh instances try to call them at once.

# If this fails, don't bother trying to build the other targets.

[ -z "$NO_CLEAN" ] && blank_tempdir build

mkdir -p build/logs &&
(EXTRACT_ALL=1 ./download.sh 2>&1 &&
 ./host-tools.sh 2>&1 &&
 ./simple-cross-compiler.sh 2>&1 "$CROSS_COMPILER_HOST" ||
 dienow) | tee build/logs/build-host-cc.txt | maybe_quiet

cp packages/MANIFEST build || dienow

# Adjust $CPUS so as not to overload the machine, max 2 build processes
# per gigabyte of RAM

if [ ! -z "$FORK" ] && [ -z "$CPUS" ]
then
  MEGS=$(($(awk '/MemTotal:/{print $2}' /proc/meminfo)/1024))
  TARGET_COUNT=$(find sources/targets -maxdepth 1 -type f | wc -l)
  export CPUS=$(($MEGS/($TARGET_COUNT*512)))
  [ "$CPUS" -lt 1 ] && CPUS=1
fi

# Build all non-hw targets, possibly in parallel

more/for-each-target.sh \
  './build.sh $TARGET 2>&1 | tee build/logs/build-${TARGET}.txt'

# Run smoketest.sh for each non-hw target.

more/for-each-target.sh \
  'more/smoketest.sh $TARGET 2>&1 | tee build/logs/smoketest-$TARGET.txt'

# If we have a control image, build natively

[ ! -z "$1" ] && more/buildall-native.sh "$1"

more/smoketest-report.sh | tee build/logs/status.txt
