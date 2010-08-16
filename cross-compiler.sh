#!/bin/bash

# Build a more advanced cross compiler, including thread support and uClibc++,
# built --with-shared (which produces libgcc_s.so), statically linked
# against uClibc on the host (for portability), and including the $TARGET-ldd
# and $TARGET-ldconfig utilities.

# Building this requires two existing (simple) cross compilers: one for
# the host (to build the executables) and one for the target (to build
# the libraries).

# This is a simple wrapper for native-compiler.sh, we re-use the canadian
# cross infrastructure in there to build a very similar compiler.

. sources/include.sh || exit 1

# Unless told otherwise, create statically linked i686 host binaries (which
# should run on an x86-64 host just fine, even if it hasn't got 32-bit
# libraries installed).

BUILD_STATIC=${BUILD_STATIC:-all} HOST_ARCH="${CROSS_HOST_ARCH:-i686}" \
  TOOLCHAIN_PREFIX="${1}-" STAGE_NAME=cross-compiler \
  ./native-compiler.sh "$1" || exit 1

# Run the cross compiler smoke test if requested.

if [ ! -z "$CROSS_SMOKE_TEST" ]
then
  more/cross-smoke-test.sh "$ARCH" || exit 1
fi
