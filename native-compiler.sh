#!/bin/bash

# Build a compiler for a given target, using one or more existing simple
# cross compilers.

# This can be used to build a native compiler for an aribitrary target, or to
# build a more portable and capable cross compiler for an arbitrary host.

# The new compiler is built --with-shared, with thread support, has uClibc++
# installed, and is linked against uClibc (see BUILD_STATIC in config).

source sources/include.sh && load_target "$1" || exit 1
check_for_base_arch || exit 0

check_prerequisite "${ARCH}-cc"

[ -z "$HOST_ARCH" ] && HOST_ARCH="$ARCH" || check_prerequisite "${HOST_ARCH}-cc"

mkdir -p "$STAGE_DIR/bin" || dienow

# Build C Library

build_section linux-headers
build_section uClibc

# Build binutils, gcc, and ccwrap

build_section binutils
build_section gcc
build_section ccwrap

# Tell future packages to link against the libraries in the new compiler,
# rather than the ones in the simple compiler.

export "$(echo $ARCH | sed 's/-/_/g')"_CCWRAP_TOPDIR="$STAGE_DIR"

# Add C++ standard library

[ -z "$NO_CPLUSPLUS" ] && build_section uClibc++

# For a native compiler, build make, bash, and distcc.  (Yes, this is an old
# version of Bash.  It's intentional.)

if [ -z "$TOOLCHAIN_PREFIX" ]
then
  build_section make
  build_section bash
  build_section distcc
fi

# Delete some unneeded files

[ -z "$SKIP_STRIP" ] &&
  rm -rf "$STAGE_DIR"/{info,man,libexec/gcc/*/*/install-tools}

create_stage_tarball
