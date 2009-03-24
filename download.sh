#!/bin/bash

# Use "./download.sh --extract" to extract all tarballs.

NO_ARCH=none
source sources/include.sh

[ "$1" == "--extract" ] && EXTRACT_ALL=yes

# Download everything we haven't already got a copy of.

# Note: set SHA1= blank to skip checksum validation.

echo -e "$DOWNLOAD_COLOR"
echo "=== Download source code."

# List of fallback mirrors for these files

MIRROR_LIST="http://impactlinux.com/firmware/mirror http://landley.net/code/firmware/mirror http://127.0.0.1/code/firmware/mirror"

# Note: a blank SHA1 value means accept anything, and the download script
# prints out the sha1 of such files after downloading it, so to update to
# a new version of a file, set SHA1= and update the URL, run ./download.sh,
# then cut and paste the sha1 from the output and run it again to confirm.

# Required for cross compile toolchain
URL=http://kernel.org/pub/linux/kernel/v2.6/linux-2.6.29.tar.bz2 \
SHA1=0640a2f4bea3fc272541f322b74ea365ad7f2349 \
download || dienow

URL=http://www.uclibc.org/downloads/uClibc-0.9.30.1.tar.bz2 \
SHA1=4b36fec9a0dacbd6fe0fd2cdb7836aaf8b7f4992 \
UNSTABLE=http://uclibc.org/downloads/uClibc-snapshot.tar.bz2 \
download || dienow

URL=ftp://ftp.gnu.org/gnu/binutils/binutils-2.17.tar.bz2 \
SHA1=a557686eef68362ea31a3aa41ce274e3eeae1ef0 \
UNSTABLE=ftp://ftp.gnu.org/gnu/binutils/binutils-2.18.tar.bz2 \
download || dienow

URL=ftp://ftp.gnu.org/gnu/gcc/gcc-4.1.2/gcc-core-4.1.2.tar.bz2 \
SHA1=d6875295f6df1bec4a6f4ab8f0da54bfb8d97306 \
UNSTABLE=ftp://ftp.gnu.org/gnu/gcc/gcc-4.2.1/gcc-core-4.2.1.tar.bz2 \
download || dienow

URL=http://ftp.gnu.org/gnu/gcc/gcc-4.1.2/gcc-g++-4.1.2.tar.bz2 \
SHA1=e29c6e151050f8b5ac5d680b99483df522606143 \
UNSTABLE=http://ftp.gnu.org/gnu/gcc/gcc-4.2.1/gcc-g++-4.2.1.tar.bz2 \
download || dienow

URL=http://impactlinux.com/code/toybox/downloads/toybox-0.0.9.tar.bz2 \
SHA1=a3aed07694149c6582a78cf6de4dfcff0383c9d5 \
download || dienow

# Required for native build environment

URL=http://www.busybox.net/downloads/busybox-1.13.3.tar.bz2 \
SHA1=364eefc4ff73613db530518e9882fdf66a694294 \
UNSTABLE=http://busybox.net/downloads/busybox-snapshot.tar.bz2 \
download || dienow

URL=ftp://ftp.gnu.org/gnu/make/make-3.81.tar.bz2 \
SHA1=41ed86d941b9c8025aee45db56c0283169dcab3d \
download || dienow

URL=http://ftp.gnu.org/gnu/bash/bash-2.05b.tar.gz \
SHA1=b3e158877f94e66ec1c8ef604e994851ee388b09 \
download || dienow

URL=http://cxx.uclibc.org/src/uClibc++-0.2.2.tar.bz2 \
SHA1=f5582d206378d7daee6f46609c80204c1ad5c0f7 \
download || dienow

# Optional but nice

URL=http://downloads.sourceforge.net/genext2fs/genext2fs-1.4.1.tar.gz &&
SHA1=9ace486ee1bad0a49b02194515e42573036f7392 \
download || dienow

URL=http://downloads.sourceforge.net/e2fsprogs/e2fsprogs-1.41.4.tar.gz \
SHA1=55da145bce7b024ab609aa4a6fc8be81a2bb3490 \
download || dienow

URL=http://distcc.googlecode.com/files/distcc-3.1.tar.bz2 \
SHA1=30663e8ff94f13c0553fbfb928adba91814e1b3a \
download || dienow

URL=http://downloads.sourceforge.net/sourceforge/strace/strace-4.5.18.tar.bz2 \
SHA1=50081a7201dc240299396f088abe53c07de98e4c \
download || dienow

# ftp://ftp.denx.de/pub/u-boot/u-boot-1.2.0.tar.bz2
# http://tinderbox.dev.gentoo.org/portage/scripts/bootstrap.sh
# http://cxx.uclibc.org/src/uClibc++-0.2.1.tar.bz2

echo === Got all source.

cleanup_oldfiles

# Set color back to normal.
echo -e "\e[0m"
