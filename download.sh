#!/bin/bash

# Download all the source tarballs we haven't got up-to-date copies of.

# The tarballs are downloaded into the "packages" directory, which is
# created as needed.

# The --extract option extracts/patches each tarball into "build/packages".
# (Otherwise this is done later when the tarball is first used by a build.)

[ "$1" == "--extract" ] && EXTRACT_ALL=yes

source sources/include.sh || exit 1

mkdir -p "$SRCDIR" || dienow

echo "=== Download source code."

# List of fallback mirrors for these files

MIRROR_LIST="http://impactlinux.com/firmware/mirror http://landley.net/code/firmware/mirror http://127.0.0.1/code/firmware/mirror"

# Note: set SHA1= blank to skip checksum validation.

# A blank SHA1 value means accept anything, and the download script
# prints out the sha1 of such files after downloading it.  So to update to
# a new version of a file, set SHA1= and update the URL, run ./download.sh,
# then cut and paste the sha1 from the output and run it again to confirm.

# Building a cross compile toolchain requires linux headers, uClibc,
# binutils, and gcc.

URL=http://kernel.org/pub/linux/kernel/v2.6/linux-2.6.31.6.tar.bz2 \
SHA1=00967b9eb7e2bd635425b684968761569a69479e \
UNSTABLE=http://kernel.org/pub/linux/kernel/v2.6/testing/linux-2.6.32-rc7.tar.bz2 \
download || dienow

URL=http://www.uclibc.org/downloads/uClibc-0.9.30.1.tar.bz2 \
SHA1=4b36fec9a0dacbd6fe0fd2cdb7836aaf8b7f4992 \
UNSTABLE=http://uclibc.org/downloads/uClibc-snapshot.tar.bz2 \
download || dienow

# 2.17 was the last GPLv2 release of binutils

URL=ftp://ftp.gnu.org/gnu/binutils/binutils-2.17.tar.bz2 \
SHA1=a557686eef68362ea31a3aa41ce274e3eeae1ef0 \
UNSTABLE=ftp://ftp.gnu.org/gnu/binutils/binutils-2.18.tar.bz2 \
download || dienow

# 4.2.1 was the last GPLv2 release of gcc

URL=ftp://ftp.gnu.org/gnu/gcc/gcc-4.2.1/gcc-core-4.2.1.tar.bz2 \
SHA1=43a138779e053a864bd16dfabcd3ffff04103213 \
UNSTABLE=ftp://ftp.gnu.org/gnu/gcc/gcc-4.4.1/gcc-core-4.4.1.tar.bz2 \
download || dienow

# The g++ version must match gcc version.

URL=http://ftp.gnu.org/gnu/gcc/gcc-4.2.1/gcc-g++-4.2.1.tar.bz2 \
SHA1=8f3785bd0e092f563e14ecd26921cd04275496a6 \
UNSTABLE=http://ftp.gnu.org/gnu/gcc/gcc-4.4.1/gcc-g++-4.4.1.tar.bz2 \
download || dienow

# Building a native root filesystem requires linux and uClibc (above) plus
# BusyBox.  Adding a native toolchain requires binutils and gcc (above) plus
# make and bash.

URL=http://www.busybox.net/downloads/busybox-1.15.2.tar.bz2 \
SHA1=2f396a4cb35db438a9b4af43df6224f343b8a7ae \
UNSTABLE=http://busybox.net/downloads/busybox-snapshot.tar.bz2 \
download || dienow

URL=ftp://ftp.gnu.org/gnu/make/make-3.81.tar.bz2 \
SHA1=41ed86d941b9c8025aee45db56c0283169dcab3d \
download || dienow

# This version of bash is ancient, but it provides everything most package
# builds need and is less than half the size of current versions.  Eventually,
# either busybox ash or toysh should grow enough features to replace bash.

URL=http://ftp.gnu.org/gnu/bash/bash-2.05b.tar.gz \
SHA1=b3e158877f94e66ec1c8ef604e994851ee388b09 \
download || dienow

# These are optional parts of the native root filesystem.

URL=http://impactlinux.com/code/toybox/downloads/toybox-0.1.0.tar.bz2 \
SHA1=ad42f9317e3805312c521fc62c6bfd2d4c61906c \
UNSTABLE=http://impactlinux.com/fwl/mirror/alt-toybox-0.tar.bz2
download || dienow

URL=http://cxx.uclibc.org/src/uClibc++-0.2.2.tar.bz2 \
SHA1=f5582d206378d7daee6f46609c80204c1ad5c0f7 \
download || dienow

URL=http://distcc.googlecode.com/files/distcc-3.1.tar.bz2 \
SHA1=30663e8ff94f13c0553fbfb928adba91814e1b3a \
download || dienow

URL=http://downloads.sf.net/sourceforge/strace/strace-4.5.18.tar.bz2 \
SHA1=50081a7201dc240299396f088abe53c07de98e4c \
download || dienow

URL=http://matt.ucc.asn.au/dropbear/releases/dropbear-0.52.tar.bz2 \
SHA1=8c1745a9b64ffae79f28e25c6fe9a8b96cac86d8 \
download || dienow

# The following packages are built and run on the host only.  (host-tools.sh
# also builds host versions of many packages in the native root filesystem,
# but the following packages are not cross compiled for the target, and thus
# do not wind up in the system image.)

URL=http://downloads.sf.net/genext2fs/genext2fs-1.4.1.tar.gz &&
SHA1=9ace486ee1bad0a49b02194515e42573036f7392 \
download || dienow

URL=http://downloads.sf.net/e2fsprogs/e2fsprogs-1.41.8.tar.gz \
SHA1=e86b33d8997d24ceaf6e64afa20bfc7f5f2425b4 \
download || dienow

URL=http://downloads.sf.net/squashfs/squashfs4.0.tar.gz \
SHA1=3efe764ac27c507ee4a549fc6507bc86ea0660dd \
RENAME="s/(squashfs)(.*)/\1-\2/" \
download || dienow

# Todo:

# ftp://ftp.denx.de/pub/u-boot/u-boot-1.2.0.tar.bz2

echo === Got all source.

rm -f "$SRCDIR"/MANIFEST

cleanup_oldfiles

# Create a MANIFEST file listing package versions.

# This can optionally call source control systems (hg and svn) to get version
# information for the FWL build scripts and any USE_UNSTABLE packages.  These
# are intentionally excluded from the new path setup by host-tools.sh, so
# just in case we've already run that use $OLDPATH for this.

blank_tempdir "$WORK"
PATH="$OLDPATH" do_readme > "$SRCDIR"/MANIFEST || dienow

# Set color back to normal.
echo -e "\e[0m"
