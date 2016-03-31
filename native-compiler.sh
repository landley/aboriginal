#!/bin/bash

# Build a compiler for a given target, using one or more existing simple
# cross compilers.

# This can be used to build a native compiler for an aribitrary target, or to
# build a more portable and capable cross compiler for an arbitrary host.

# The new compiler is built --with-shared, with thread support, has uClibc++
# installed, and is linked against musl (see BUILD_STATIC in config).

source sources/include.sh && load_target "$1" || exit 1
check_for_base_arch || exit 0

check_prerequisite "${CC_PREFIX}cc"

[ -z "$HOST_ARCH" ] && HOST_ARCH="$ARCH" && STAGE_DIR="$STAGE_DIR/usr" ||
  check_prerequisite "${HOST_ARCH}-cc"

mkdir -p "$STAGE_DIR/bin" || dienow

# Build C Library

if [ ! -z "$KARCH" ]
then
  build_section linux-headers
  if [ -z "$UCLIBC_CONFIG" ] || [ ! -z "$MUSL" ]
  then 
    build_section musl
  else
    build_section uClibc
  fi
fi

# Build binutils, gcc, and ccwrap, using the gplv3 variant if requested
VARIANT=
[ ! -z "$ENABLE_GPLV3" ] && VARIANT="gplv3"

build_section binutils $VARIANT
[ ! -z "$ELF2FLT" ] && build_section elf2flt
build_section gcc $VARIANT
build_section ccwrap

# Tell future packages to link against the libraries in the new compiler,
# rather than the ones in the simple compiler.

export "$(echo $ARCH | sed 's/-/_/g')"_CCWRAP_TOPDIR="$STAGE_DIR"

if [ ! -z "$KARCH" ]
then
  # Add C++ standard library (if we didnt build one in GCC 5.3)

  [ -z "$NO_CPLUSPLUS" ] && [ -z "$ENABLE_GPLV3" ] && build_section uClibc++

  # For a native compiler, build make, bash, and distcc.  (Yes, this is an old
  # version of Bash.  It's intentional.)

  if [ -z "$TOOLCHAIN_PREFIX" ]
  then
    build_section make
    build_section bash
    build_section distcc
    cp "$SOURCES/toys/hdainit.sh" "$STAGE_DIR/../init" &&
    mv "$STAGE_DIR"/{man,share/man} || dienow
  fi
fi

# Delete some unneeded files and strip everything else
rm -rf "$STAGE_DIR"/{info,libexec/gcc/*/*/install-tools} || dienow
if [ -z "$SKIP_STRIP" ]
then
  "${ARCH}-strip" --strip-unneeded "$STAGE_DIR"/lib/*.so
  "${ARCH}-strip" "$STAGE_DIR"/{bin/*,sbin/*}
fi

create_stage_tarball
