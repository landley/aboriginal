#!/bin/bash

# Package a root filesystem directory into a filesystem image file

source sources/include.sh || exit 1

# Parse sources/targets/$1

load_target "$1"

check_for_base_arch || exit 0

# Which directory do we package up?

if [ -z "$NATIVE_ROOT" ]
then
  [ -z "$NO_NATIVE_COMPILER" ] &&
    NATIVE_ROOT="$BUILD/root-filesystem-$ARCH"

  [ -e "$NATIVE_ROOT" ] ||
    NATIVE_ROOT="$BUILD/simple-root-filesystem-$ARCH"
fi

if [ ! -d "$NATIVE_ROOT" ]
then
  [ -z "$FAIL_QUIET" ] && echo No "$NATIVE_ROOT" >&2
  exit 1
fi

[ -z "$SYSIMAGE_TYPE" ] && SYSIMAGE_TYPE=squashfs

echo "Generating $SYSIMAGE_TYPE root filesystem from $NATIVE_ROOT."

SYSIMAGE_TYPE="$SYSIMAGE_TYPE" image_filesystem "$NATIVE_ROOT" "$STAGE_DIR/hda"

create_stage_tarball

echo Image generation complete.
