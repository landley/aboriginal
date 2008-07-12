#!/bin/bash

# Use "./download.sh --extract" to extract all tarballs.

NO_ARCH=none
source include.sh

[ x"$1" == x--extract ] && EXTRACT_ALL=yes

# Dark blue
echo -e "\e[34m"

# Download everything we haven't already got a copy of.

# Note: set SHA1= blank to skip checksum validation.

echo "=== Download source code." &&

# Note, a blank SHA1 value means accept anything, and the download script
# prints out the sha1 of such files after downloading it, so to update to
# a new version of a file, set SHA1= and updat the URL, run ./download.sh,
# then cut and paste the sha1 from the output and run it again to confirm.

# Required for cross compile toolchain
URL=http://kernel.org/pub/linux/kernel/v2.6/linux-2.6.25.10.tar.bz2 \
SHA1=2911e1c01cd75d7e0fad2afb8329cd8ad1e742fb \
download &&

URL=http://www.uclibc.org/downloads/uClibc-0.9.29.tar.bz2 \
SHA1=1c5a36dc2cfa58b41db413190e45675c44ca4691 \
download &&
#URL=http://uclibc.org/downloads/snapshots/uClibc-20070924.tar.bz2 \
#SHA1= \
#download &&

URL=ftp://ftp.gnu.org/gnu/binutils/binutils-2.17.tar.bz2 \
SHA1=a557686eef68362ea31a3aa41ce274e3eeae1ef0 \
download &&

URL=ftp://ftp.gnu.org/gnu/gcc/gcc-4.1.2/gcc-core-4.1.2.tar.bz2 \
SHA1=d6875295f6df1bec4a6f4ab8f0da54bfb8d97306 \
download &&

URL=http://ftp.gnu.org/gnu/gcc/gcc-4.1.2/gcc-g++-4.1.2.tar.bz2 \
SHA1=e29c6e151050f8b5ac5d680b99483df522606143 \
download &&

URL=http://landley.net/code/toybox/downloads/toybox-0.0.6.tar.bz2 \
SHA1=188c602a89dc6a53144a65e2fed92696a3d24444 \
download &&

# Ye olde emulator

#URL=http://qemu.org/qemu-0.9.0.tar.gz \
#SHA1=1e57e48a06eb8729913d92601000466eecef06cb \
#download &&

# Required for native build environment

URL=http://superb-east.dl.sourceforge.net/sourceforge/squashfs/squashfs3.1.tar.gz \
SHA1=89d537fd18190402ff226ff885ddbc14f6227a9b \
download &&

URL=http://www.busybox.net/downloads/busybox-1.11.0.tar.bz2 \
SHA1=03738bbaa2be1676de37d1696e0a7f99ba27324f \
download &&

URL=ftp://ftp.gnu.org/gnu/make/make-3.81.tar.bz2 \
SHA1=41ed86d941b9c8025aee45db56c0283169dcab3d \
download &&

URL=http://ftp.gnu.org/gnu/bash/bash-2.05b.tar.gz \
SHA1=b3e158877f94e66ec1c8ef604e994851ee388b09 \
download &&

URL=http://superb-east.dl.sourceforge.net/sourceforge/strace/strace-4.5.14.tar.bz2 \
SHA1=72c17d1dd6786d22ca0aaaa7292b8edcd70a27de \
download &&

# We look for things.  Things that make us go.  (Laxatives, aisle 7.)
URL=http://distcc.samba.org/ftp/distcc/distcc-2.18.3.tar.bz2 \
SHA1=88e4c15826bdbc5a3de0f7c1bcb429e558c6976d \
download &&

# ftp://ftp.denx.de/pub/u-boot/u-boot-1.2.0.tar.bz2
# http://tinderbox.dev.gentoo.org/portage/scripts/bootstrap.sh
# http://cxx.uclibc.org/src/uClibc++-0.2.1.tar.bz2

echo === Got all source. &&

cleanup_oldfiles &&

# Set color back to normal.
echo -e "\e[0m"
