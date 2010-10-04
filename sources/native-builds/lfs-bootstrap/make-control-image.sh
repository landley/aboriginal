#!/bin/bash

# Build Linux From Scratch 6.7 packages under target environment.

# Note: this doesn't rebuild the toolchain packages (libc, binutils,
# gcc, linux-headers), but reuses the toolchain we've got, because:

# 1) Building a new toolchain is a target-dependent can of worms.
# 2) Doing so would lose distcc acceleration.
# 3) Building glibc under uClibc is buggy because glibc expects that a
#    2.6 kernel will have TLS, and uClibc without NPTL doesn't.  (Yes,
#    repeat after me, "autoconf is useless".)

source sources/include.sh || exit 1

# Find path to our working directory.

[ $# -ne 1 ] && echo "usage: $0 FILENAME" >&2 && exit 1
[ "$1" != "/dev/null" ] && [ -e "$1" ] && echo "$1" exists && exit 0

# We use a lot of our own directories because we may have the same packages
# as the aboriginal build, but use different versions.  So keep things separate
# so they don't interfere.

MYDIR="$(dirname "$(readlink -f "$(which "$0")")")"
IMAGENAME="${MYDIR/*\//}"
#PATCHDIR="$MYDIR/patches"
SRCDIR="$SRCDIR/$IMAGENAME" && mkdir -p "$SRCDIR" || dienow
WORK="$WORK/$IMAGENAME" && blank_tempdir "$WORK"
SRCTREE="$WORK"
PATCHDIR="$SRCTREE"

echo "=== Download source code."

EXTRACT_ALL=1

# Download upstream tarball

PATCHDIR="$SRCTREE"

URL=http://ftp.osuosl.org/pub/lfs/lfs-packages/lfs-packages-6.7.tar \
SHA1= \
RENAME='s/-sources//' \
download || dienow

cleanup_oldfiles

SRCDIR="$SRCTREE/lfs-packages"
PATCHDIR="$SRCDIR"

# Fixups for tarball names the Aboriginal extract scripts can't parse

mv "$SRCDIR"/sysvinit-2.88{dsf,}.tar.bz2 &&
mv "$SRCDIR"/tcl{8.5.8-src,-src-8.5.8}.tar.gz &&
mv "$SRCDIR"/udev-{161-testfiles,testfiles-161}.tar.bz2 || exit 1

# Remove damaged patches (either whitespace damaged, or don't apply without
# "fuzz" support).

rm "$SRCDIR"/gcc-4.5.1-startfiles_fix-1.patch &&
rm "$SRCDIR"/tar-1.23-overflow_fix-1.patch || exit 1

# Break down upstream tarball

for i in $(cd "$SRCDIR"; ls *.tar.*)
do
  extract_package $(noversion $i)
done

#URL=http://ftp.gnu.org/pub/gnu/ncurses/ncurses-5.7.tar.gz \
#SHA1=8233ee56ed84ae05421e4e6d6db6c1fe72ee6797 \
#maybe_fork "download || dienow"

