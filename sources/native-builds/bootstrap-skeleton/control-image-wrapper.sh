#!/bin/bash

# Control image generator infrastructure.

source sources/include.sh || exit 1

# Did caller specify the name of a control image to generate?  Explicit
# /dev/null means none.

[ $# -ne 1 ] && echo "usage: $0 FILENAME" >&2 && exit 1
[ "$1" != "/dev/null" ] && [ -e "$1" ] && echo "$1" exists && exit 0

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

cp "$MYDIR"/../bootstrap-skeleton/files/* "$WORK" || exit 1
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

if [ "$1" != "/dev/null" ]
then
  cd "$TOP" &&
  mksquashfs "$WORK" "$1" -noappend -all-root || dienow
fi
