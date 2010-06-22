#!/bin/bash

# Combine the output of simple-root-filesystem and native-compiler.

. sources/include.sh || exit 1

read_arch_dir "$1"

[ ! -d "$BUILD/simple-root-filesystem-$ARCH" ] &&
  echo "No $BUILD/simple-root-filesystem-$ARCH" >&2 &&
  exit 1

[ ! -d "$BUILD/native-compiler-$ARCH" ] &&
  echo "No $BUILD/native-compiler-$ARCH" >&2 &&
  exit 1

cp -a "$BUILD/simple-root-filesystem-$ARCH/." "$STAGE_DIR" || dienow

# Remove shared libraries copied from cross compiler.

rm -rf "$BUILD/root-filesystem-$ARCH/usr/lib" 2>/dev/null

# Copy native compiler, but do not overwrite existing files (which could
# do bad things to busybox).

[ -z "$ROOT_NODIRS" ] && USRDIR="/usr" || USRDIR=""
yes 'n' | cp -ia "$BUILD/native-compiler-$ARCH/." \
  "$BUILD/root-filesystem-$ARCH$USRDIR" 2>/dev/null || dienow

create_stage_tarball
