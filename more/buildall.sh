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

if [ -z "$BUILD_NATIVE_ONLY" ]
then
  [ -z "$NO_CLEAN" ] && blank_tempdir build

  mkdir -p build/logs &&
  (EXTRACT_ALL=1 ./download.sh 2>&1 &&
   ./host-tools.sh 2>&1 &&
   ./simple-cross-compiler.sh 2>&1 "$CROSS_COMPILER_HOST" ||
   dienow) | tee build/logs/build-host-cc.txt | maybe_quiet

  cp packages/MANIFEST build || dienow

  # Build all non-hw targets, possibly in parallel

  more/for-each-target.sh \
    './build.sh $TARGET 2>&1 | tee build/logs/build-${TARGET}.txt'

  more/build-control-images.sh

  # Run smoketest.sh for each non-hw target.

  more/for-each-target.sh \
    'more/smoketest.sh $TARGET 2>&1 | tee build/logs/smoketest-$TARGET.txt'

fi

# Build the hdb images sequentially without timeout.sh, to avoid potential
# I/O storm triggering timeouts

FORK= more/for-each-target.sh \
  '. sources/toys/make-hdb.sh; HDBMEGS=2048; HDB=build/system-image-$TARGET/hdb.img; echo "$HDB"; rm -f "$HDB"; make_hdb'

# Build static-tools (dropbear and strace) for each target

mkdir -p build/native-static || dienow
more/for-each-target.sh \
  'ln -sf ../native-static build/system-image-$TARGET/upload'

more/for-each-target.sh \
  'more/timeout.sh 60 "HDB=hdb.img more/native-build-from-build.sh $TARGET build/control-images/static-tools.hdc | tee build/logs/native-$TARGET.txt"'

# If using a test version of busybox, run busybox test suite.

is_in_list busybox "$USE_UNSTABLE" &&
  more/for-each-target.sh \
    'more/timeout.sh 60 "HDB=hdb.img more/native-build-from-build.sh $TARGET build/control-images/busybox-test.hdc" | tee build/logs/busybox-test-$TARGET.txt'

# Create a file containing simple pass/fail results for all architectures.

more/smoketest-report.sh | tee build/logs/status.txt
