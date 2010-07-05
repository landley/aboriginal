#!/bin/bash

# Build every target architecture, creating build-$ARCH.txt log files.
# If $FORK is set, build them in parallel.

. sources/functions.sh || exit 1

[ -z "$STATIC_CC_HOST" ] && export STATIC_CC_HOST=i686

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

more/for-each-target.sh \
  './build.sh $TARGET 2>&1 | tee build/logs/build-${TARGET}.txt'

# Run smoketest.sh for each non-hw target.

more/for-each-target.sh \
  'more/smoketest.sh $TARGET 2>&1 | tee build/logs/smoketest-$TARGET.txt'

more/build-control-images.sh

# Build all control images

mkdir -p build/control-images || dienow
for i in sources/native-builds/*.sh
do
  X=$(echo $i | sed 's@.*/\(.*\)\.sh@\1@')
  # Don't use maybe_fork here, the extract stages conflict.
  $i build/control-images/${X}.hdc | maybe_quiet
done

wait

# Build static-tools (dropbear and strace) for each target

mkdir -p build/native-static &&
more/for-each-target.sh \
  'more/timeout.sh 60 "(cd build/system-image-$TARGET && ln -s ../native-static upload && ./native-build.sh ../control-images/static-tools.hdc) | tee build/logs/native-$TARGET.txt"'

# Create a file containing simple pass/fail results for all architectures.

more/smoketest-all.sh --logs | tee build/logs/status.txt
