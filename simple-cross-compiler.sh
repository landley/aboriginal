#!/bin/bash

# Build a simple cross compiler for the specified target.

# This simple compiler has no thread support, no libgcc_s.so, doesn't include
# uClibc++, and is dynamically linked against the host's shared libraries.

# Its stripped down nature makes it easy to build on an arbitrary host, and
# provides just enough capability to build a root filesystem, and to be used
# as a distcc accelerator from within that system.


# Get lots of predefined environment variables and shell functions.

source sources/include.sh || exit 1

# Parse sources/targets/$1

load_target "$1"

# If this target has a base architecture that's already been built, use that.

check_for_base_arch || exit 0

export TOOLCHAIN_PREFIX="${ARCH}-"

if [ -z "$ENABLE_GPLV3" ]
then

  # Build GPLv2 toolchain
  build_section binutils
  [ ! -z "$ELF2FLT" ] && build_section elf2flt
  build_section gcc
  build_section ccwrap
else

  # Build GPLv3 toolchain, order is a bit different
  build_section binutils gplv3
  [ ! -z "$ELF2FLT" ] && build_section elf2flt
  BASE_GCC=1 build_section gcc gplv3
fi


if [ ! -z "$KARCH" ]
then

  # Build C Library

  build_section linux-headers

  if [ -z "$UCLIBC_CONFIG" ] || [ ! -z "$MUSL" ]
  then
    build_section musl
  else
    build_section uClibc
  fi
fi

# Build the rest of the GPLv3 toolchain
if [ ! -z "$ENABLE_GPLV3" ]
then
  build_section gcc gplv3
  build_section ccwrap
fi

[ ! -z "$KARCH" ] && cat > "${STAGE_DIR}"/README << EOF
Cross compiler for $ARCH from http://landley.net/aboriginal

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

if [ ! -z "$KARCH" ]
then
  # A quick hello world program to test the cross compiler out.
  # Build hello.c dynamic, then static, to verify header/library paths.

  echo "Sanity test: building Hello World."

  "${ARCH}-gcc" -Os "${SOURCES}/root-filesystem/src/hello.c" -o "$WORK"/hello &&
  "${ARCH}-gcc" -Os -static "${SOURCES}/root-filesystem/src/hello.c" \
  	-o "$WORK"/hello || dienow

  # If we build GCC 5.3, it needs to have a working C++ compiler
  if [ ! -z "$ENABLE_GPLV3" ]
  then
    echo "Sanity test: building C++ Hello World."
    "${ARCH}-g++" -Os "${SOURCES}/root-filesystem/src/hello.cpp" -o "$WORK"/hello &&
      "${ARCH}-g++" -Os -static "${SOURCES}/root-filesystem/src/hello.cpp" \
  		    -o "$WORK"/hello || dienow
  fi

  # Does the hello world we just built actually run?

  if [ ! -z "$CROSS_SMOKE_TEST" ]
  then
    more/cross-smoke-test.sh "$ARCH" || exit 1
  fi
fi

# Tar it up

create_stage_tarball

echo -e "\e[32mCross compiler toolchain build complete.\e[0m"
