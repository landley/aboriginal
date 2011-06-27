#!/bin/bash

# Combine the output of simple-root-filesystem and native-compiler.

. sources/include.sh || exit 1

load_target "$1"

check_for_base_arch || exit 0

[ ! -d "$BUILD/simple-root-filesystem-$ARCH" ] &&
  echo "No $BUILD/simple-root-filesystem-$ARCH" >&2 &&
  exit 1

[ ! -d "$BUILD/native-compiler-$ARCH" ] &&
  echo "No $BUILD/native-compiler-$ARCH" >&2 &&
  exit 1

cp -al "$BUILD/simple-root-filesystem-$ARCH/." "$STAGE_DIR" || dienow

# Remove shared libraries copied from cross compiler, and let /bin/sh point
# to bash out of native compiler instead of busybox shell.

rm -rf "$BUILD/root-filesystem-$ARCH/"{usr/lib,bin/sh} 2>/dev/null

# Copy native compiler, but do not overwrite existing files (which could
# do bad things to busybox).

[ -z "$ROOT_NODIRS" ] && USRDIR="/usr" || USRDIR=""
yes 'n' | cp -ial "$BUILD/native-compiler-$ARCH/." \
  "$BUILD/root-filesystem-$ARCH$USRDIR" 2>/dev/null || dienow

# Strip everything again, just to be sure.

if [ -z "$SKIP_STRIP" ]
then
  "${ARCH}-strip" --strip-unneeded "$STAGE_DIR"/lib/*.so
  "${ARCH}-strip" "$STAGE_DIR"/{bin/*,sbin/*}
fi

create_stage_tarball
