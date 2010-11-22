#!/bin/bash

# Control image generator infrastructure.

source sources/include.sh || exit 1

# Find path to our working directory.

MYDIR="$(readlink -f "$(dirname "$(which "$0")")")"
IMAGENAME="${MYDIR/*\//}"

# Use our own directories for downloaded source tarballs and patches.
# (We may have the same packages as the aboriginal build, but use different
# versions, and we don't want our cleanup_oldfiles to overlap.)

PATCHDIR="$MYDIR/patches"
SRCDIR="$SRCDIR/control-images/$IMAGENAME" && mkdir -p "$SRCDIR" || dienow

# Include package cache in the control image, so the target system image can
# build from this source.

WORK="$BUILD/control-images/$IMAGENAME" &&
blank_tempdir "$WORK" &&
SRCTREE="$WORK/packages" &&
mkdir "$SRCTREE" &&

# Copy common infrastructure to target

cp "$MYDIR"/../bootstrap-skeleton/mnt/* "$WORK" || exit 1
if [ -e "$MYDIR/mnt" ]
then
  cp -a "$MYDIR/mnt/." "$WORK" || exit 1
fi

# Populate packages directory

echo "=== $IMAGENAME: Download/extract source code"

EXTRACT_ALL=1

source "$MYDIR"/download.sh || exit 1

cleanup_oldfiles

# Create sqaushfs image

mksquashfs "$WORK" "$WORK.hdc" -noappend -all-root || dienow
