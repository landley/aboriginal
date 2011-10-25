#!/bin/bash

# Download all the source tarballs we haven't got up-to-date copies of.

# The tarballs are downloaded into the "packages" directory, which is
# created as needed.

source sources/include.sh || exit 1

mkdir -p "$SRCDIR" || dienow

echo "=== Download source code."

# Note: set SHA1= blank to skip checksum validation.

# A blank SHA1 value means accept anything, and the download script
# prints out the sha1 of such files after downloading it.  So to update to
# a new version of a file, set SHA1= and update the URL, run ./download.sh,
# then cut and paste the sha1 from the output and run it again to confirm.

# Building a cross compile toolchain requires linux headers, uClibc,
# binutils, and gcc.

URL=http://www.kernel.org/pub/linux/kernel/v3.x/linux-3.1.tar.bz2 \
SHA1=ac792701561b1cd4279302b8bb8f474731762ad1 \
ALT=http://kernel.org/pub/linux/kernel/v3.0/testing/linux-3.0-rc1.tar.bz2 \
maybe_fork "download || dienow"

URL=http://uclibc.org/downloads/uClibc-0.9.32.tar.bz2 \
SHA1=f8edc4ffcd9e8d1e8ae5348b9b879f5175010e67 \
ALT=http://uclibc.org/downloads/uClibc-snapshot.tar.bz2 \
maybe_fork "download || dienow"

# 2.17 was the last GPLv2 release of binutils

URL=ftp://ftp.gnu.org/gnu/binutils/binutils-2.17.tar.bz2 \
SHA1=a557686eef68362ea31a3aa41ce274e3eeae1ef0 \
ALT=ftp://ftp.gnu.org/gnu/binutils/binutils-2.18.tar.bz2 \
maybe_fork "download || dienow"

# 4.2.1 was the last GPLv2 release of gcc

URL=ftp://ftp.gnu.org/gnu/gcc/gcc-4.2.1/gcc-core-4.2.1.tar.bz2 \
SHA1=43a138779e053a864bd16dfabcd3ffff04103213 \
#ALT=ftp://ftp.gnu.org/gnu/gcc/gcc-4.4.1/gcc-core-4.4.1.tar.bz2 \
maybe_fork "download || dienow"

# The g++ version must match gcc version.

URL=http://ftp.gnu.org/gnu/gcc/gcc-4.2.1/gcc-g++-4.2.1.tar.bz2 \
SHA1=8f3785bd0e092f563e14ecd26921cd04275496a6 \
#ALT=http://ftp.gnu.org/gnu/gcc/gcc-4.4.1/gcc-g++-4.4.1.tar.bz2 \
maybe_fork "download || dienow"

# Building a native root filesystem requires linux and uClibc (above) plus
# BusyBox.  Adding a native toolchain requires binutils and gcc (above) plus
# make and bash.

URL=http://www.busybox.net/downloads/busybox-1.19.2.tar.bz2 \
SHA1=6dedaa62af98a8541901a30c3e400ce9e077ee16 \
#ALT=http://busybox.net/downloads/busybox-snapshot.tar.bz2 \
maybe_fork "download || dienow"

URL=ftp://ftp.gnu.org/gnu/make/make-3.81.tar.bz2 \
SHA1=41ed86d941b9c8025aee45db56c0283169dcab3d \
maybe_fork "download || dienow"

# This version of bash is ancient, but it provides everything most package
# builds need and is less than half the size of current versions.  Eventually,
# either busybox ash or toysh should grow enough features to replace bash.

URL=http://ftp.gnu.org/gnu/bash/bash-2.05b.tar.gz \
SHA1=b3e158877f94e66ec1c8ef604e994851ee388b09 \
maybe_fork "download || dienow"

# These are optional parts of the native root filesystem.

URL=http://cxx.uclibc.org/src/uClibc++-0.2.2.tar.bz2 \
SHA1=f5582d206378d7daee6f46609c80204c1ad5c0f7 \
maybe_fork "download || dienow"

URL=http://distcc.googlecode.com/files/distcc-3.1.tar.bz2 \
SHA1=30663e8ff94f13c0553fbfb928adba91814e1b3a \
maybe_fork "download || dienow"

# The following packages are built and run on the host only.  (host-tools.sh
# also builds host versions of many packages in the native root filesystem,
# but the following packages are not cross compiled for the target, and thus
# do not wind up in the system image.)

URL=http://downloads.sf.net/genext2fs/genext2fs-1.4.1.tar.gz &&
SHA1=9ace486ee1bad0a49b02194515e42573036f7392 \
maybe_fork "download || dienow"

URL=http://downloads.sf.net/e2fsprogs/e2fsprogs-1.41.14.tar.gz \
SHA1=24f9364fa3d4c0d7d00cb627b819d0e51055d6c5 \
maybe_fork "download || dienow"

URL=http://zlib.net/zlib-1.2.5.tar.bz2 \
SHA1=543fa9abff0442edca308772d6cef85557677e02 \
maybe_fork "download || dienow"

URL=http://downloads.sf.net/squashfs/squashfs4.2.tar.gz \
SHA1=e0944471ff68e215d3fecd464f30ea6ceb635fd7 \
RENAME="s/(squashfs)(.*)/\1-\2/" \
maybe_fork "download || dienow"

rm -f "$SRCDIR"/MANIFEST  # So cleanup_oldfiles doesn't warn about it.
cleanup_oldfiles

echo === Got all source.

# Create a MANIFEST file listing package versions.

# This can optionally call source control systems (hg and svn) to get version
# information for the build scripts and any USE_ALT packages.  These
# are intentionally excluded from the new path setup by host-tools.sh, so
# just in case we've already run that use $OLDPATH for this.

PATH="$OLDPATH" do_manifest > "$SRCDIR"/MANIFEST || dienow
