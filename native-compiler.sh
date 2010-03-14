#!/bin/bash

# Build a compiler for a given target

source sources/include.sh || exit 1
read_arch_dir "$1"
check_for_base_arch || exit 0
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

# Tell future packages to link against the libraries in the new root filesystem,
# rather than the ones in the cross compiler directory.

export "$(echo $ARCH | sed 's/-/_/g')"_CCWRAP_TOPDIR="$STAGE_DIR"

build_section uClibc++

# Delete some unneeded files

[ -z "$SKIP_STRIP" ] && rm -rf "$STAGE_DIR"/{info,man}

create_stage_tarball
