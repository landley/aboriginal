#!/bin/bash

# Script to extend minimal native build environment into a Gentoo stage 1.

# We take some liberties with this stage 1: use busybox instead of gnu tools,
# uClibc-based instead of glibc-based, and using our existing toolchain
# (with distcc acceleration).

# GFS used:
# setup-base-packages.sh
#   strace, Python, ncurses, bash, tar, patch, findutils, file, pax-utils,
#   shadow
# setup-portage.sh
#   /etc/passwd (root and portage), /etc/group (root and portage)
#   portage

# Download all the source tarballs we haven't got up-to-date copies of.

# The tarballs are downloaded into the "packages" directory, which is
# created as needed.

source sources/include.sh || exit 1

[ $# -ne 1 ] && echo "usage: $0 FILENAME" >&2 && exit 1
[ -e "$1" ] && echo "$1" exists && exit 0

# We use a lot of our own directories because we may have the same packages
# as the aboriginal build, but use different versions.  So keep things separate
# so they don't interfere.

NATIVE_BUILDS="$SOURCES/native-builds"
PATCHDIR="$NATIVE_BUILDS/gentoo-stage1-patches"
SRCDIR="$SRCDIR/gentoo-stage1" && mkdir -p "$SRCDIR" || dienow
WORK="$WORK"/gentoo-stage1 && blank_tempdir "$WORK"
SRCTREE="$WORK"

EXTRACT_ALL=1

echo "=== Download source code."

# Note: set SHA1= blank to skip checksum validation.

URL=http://zlib.net/zlib-1.2.5.tar.bz2 \
SHA1=543fa9abff0442edca308772d6cef85557677e02 \
maybe_fork "download || dienow"

URL=http://ftp.gnu.org/pub/gnu/ncurses/ncurses-5.7.tar.gz \
SHA1=8233ee56ed84ae05421e4e6d6db6c1fe72ee6797 \
maybe_fork download || dienow

URL=http://python.org/ftp/python/2.6.5/Python-2.6.5.tar.bz2 \
SHA1=24c94f5428a8c94c9d0b316e3019fee721fdb5d1 \
maybe_fork download || dienow

URL=http://ftp.gnu.org/gnu/bash/bash-3.2.tar.gz \
SHA1=fe6466c7ee98061e044dae0347ca5d1a8eab4a0d \
maybe_fork download || dienow 

URL=http://dev.gentoo.org/~zmedico/portage/archives/portage-2.1.8.tar.bz2 \
SHA1=390c97f3783af2d9e52482747ead3681655ea9c3 \
maybe_fork download || dienow

echo === Got all source.

cleanup_oldfiles

cp -a "$NATIVE_BUILDS/gentoo-stage1-files/." "$WORK" &&
cd "$TOP" &&
mksquashfs "$WORK" "$1" -noappend -all-root || dienow
