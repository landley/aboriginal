#!/bin/bash

# Build a compiler for a given target, using one or more existing simple
# cross compilers.

# This can be used to build a native compiler for an aribitrary target, or to
# build a more portable and capable cross compiler for an arbitrary host.

# The new compiler is built --with-shared and has uClibc++ installed, and is
# statically linked against uClibc (for portability) unless BUILD_STATIC=none.

source sources/include.sh && read_arch_dir "$1" || exit 1
check_for_base_arch || exit 0

# Building a cross compiler requires _two_ existing simple compilers: one for
# the host (to build the executables), and one for the target (to build
# the libraries).  For native compilers both checks test for the same thing.

check_prerequisite "${ARCH}-cc"
check_prerequisite "${FROM_ARCH}-cc"

mkdir -p "$STAGE_DIR/bin" || dienow

STATIC_FLAGS="$STATIC_DEFAULT_FLAGS"

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

build_section uClibc++

# For a native compiler, build make, bash, and distcc.  (Yes, this is an old
# version of Bash.  It's intentional.)

if [ "$FROM_ARCH" == "$ARCH" ]
then
  build_section make
  build_section bash
  build_section distcc
fi

# Delete some unneeded files

[ -z "$SKIP_STRIP" ] &&
  rm -rf "$STAGE_DIR"/{info,man,libexec/gcc/*/*/install-tools}

create_stage_tarball
