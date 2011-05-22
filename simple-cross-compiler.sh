#!/bin/bash

# Build a simple cross compiler for the specified target.

# This simple compiler has no thread support, no libgcc_s.so, doesn't include
# uClibc++, and is dynamically linked against the host's shared libraries.

# Its stripped down nature makes it easy to build on an arbitrary host, and
# provides just enough capability to build a root filesystem, and to be used
# as a distcc accelerator from within that system.


# Get lots of predefined environment variables and shell functions.

source sources/include.sh || exit 1

# Parse the sources/targets/$1 directory

read_arch_dir "$1"

# If this target has a base architecture that's already been built, use that.

check_for_base_arch || exit 0

export TOOLCHAIN_PREFIX="${ARCH}-"

# Build binutils, gcc, and ccwrap

build_section binutils
build_section gcc
build_section ccwrap

# Build C Library

build_section linux-headers
build_section uClibc

cat > "${STAGE_DIR}"/README << EOF &&
Cross compiler for $ARCH from http://aboriginal.impactlinux.com

To use: Add the "bin" subdirectory to your \$PATH, and use "$ARCH-cc" as
your compiler.

The syntax used to build the Linux kernel is:

  make ARCH=${KARCH} CROSS_COMPILE=${ARCH}-

EOF

# Strip the binaries

if [ -z "$SKIP_STRIP" ]
then
  cd "$STAGE_DIR"
  for i in `find bin -type f` `find "$CROSS_TARGET" -type f`
  do
    strip "$i" 2> /dev/null
  done
fi

# A quick hello world program to test the cross compiler out.
# Build hello.c dynamic, then static, to verify header/library paths.

echo "Sanity test: building Hello World."

"${ARCH}-gcc" -Os "${SOURCES}/toys/hello.c" -o "$WORK"/hello &&
"${ARCH}-gcc" -Os -static "${SOURCES}/toys/hello.c" -o "$WORK"/hello || dienow

# Does the hello world we just built actually run?

if [ ! -z "$CROSS_SMOKE_TEST" ]
then
  more/cross-smoke-test.sh "$ARCH" || exit 1
fi

# Tar it up

create_stage_tarball

echo -e "\e[32mCross compiler toolchain build complete.\e[0m"
