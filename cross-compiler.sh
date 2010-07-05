#!/bin/bash

# Build a more advanced cross compiler, including thread support and uClibc++,
# built --with-shared (which produces libgcc_s.so), and statically linked
# against uClibc on the host (for portability).

# Building this requires two existing (simple) cross compilers: one for
# the host (to build the executables) and one for the target (to build
# the libraries).

# This is a simple wrapper for native-compiler.sh, we re-use the canadian
# cross infrastructure in there to build a very similar compiler.


# Unless told otherwise, create statically linked i686 host binaries (which
# should run on an x86-64 host just fine, even if it hasn't got 32-bit
# libraries installed).

HOST_ARCH="${CROSS_HOST_ARCH:-i686}" BUILD_STATIC=${BUILD_STATIC:-all} \
  STAGE_NAME=cross-compiler ./native-compiler.sh "$1" || exit 1

# Run the cross compiler smoke test if requested.

if [ ! -z "$CROSS_SMOKE_TEST" ]
then
  more/cross-smoke-test.sh "$ARCH" || exit 1
fi
