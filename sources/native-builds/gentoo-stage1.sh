#!/bin/bash

# Script to extend minimal native build environment into a Gentoo stage 1.

# We take some liberties with this stage 1: use busybox instead of gnu tools,
# uClibc-based instead of glibc-based, and using our existing toolchain
# (with distcc acceleration).

# Download all the source tarballs we haven't got up-to-date copies of.

# The tarballs are downloaded into the "packages" directory, which is
# created as needed.

source sources/include.sh || exit 1

[ $# -ne 1 ] && echo "usage: $0 FILENAME" >&2 && exit 1
[ -e "$1" ] && echo "$1" exists && exit 0

SRCDIR="$SRCDIR/gentoo-stage1" && mkdir -p "$SRCDIR" || dienow
WORK="$WORK"/sub && blank_tempdir "$WORK"

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
RENAME="s/P/p/" \
maybe_fork download || dienow

echo === Got all source.

cleanup_oldfiles

# The reason this is isn't grouped together with the downloads above is when
# you download a new version but haven't deleted the old one yet, setupfor
# gets confused.

setupfor zlib
setupfor ncurses
setupfor python

cat > "$WORK"/init << 'EOF' || dienow
#!/bin/bash

upload_result()
{
  ftpput 10.0.2.2 -P $OUTPORT "$1-$ARCH" "$1"
}

set_titlebar()
{
  echo -en "\033]2;($HOST) $1\007"
  echo === "$1"
}

dotprogress()
{
  while read i; do echo -n .; done; echo
}

echo Started second stage init

# Make a chroot by copying the root filesystem we've got into a new
# (writeable) subdirectory.

touch /.iswriteable 2>/dev/null
rm /.iswriteable 2>/dev/null
if [ $? -ne 0 ]
then
  set_titlebar "writeable chroot"
  mkdir stage1
  find / -xdev | cpio -m -v -p /home/stage1 | dotprogress

  echo Restarting init script in chroot
  for i in mnt proc sys dev; do mount --bind /$i stage1/$i; done
  chroot stage1 /mnt/init
  for i in mnt proc sys dev; do umount stage1/$i; done

  if rm gentoo-stage1/.finished 2>/dev/null
  then
    set_titlebar "upload tarball"
    tar czvf gentoo-stage1.tar.gz gentoo-stage1 | dotprogress &&
    upload_result gentoo-stage1.tar.gz
  fi

  sync
  exit
fi

set_titlebar "zlib"

cp -sfR /mnt/zlib zlib &&
cd zlib &&
# 1.2.5 accidentally shipped the Makefile, then configure tries to
# modify it in place.
rm Makefile && 
./configure &&
make -j $CPUS &&
make install &&
cd .. &&
rm -rf zlib || exit 1

set_titlebar "ncurses"

cp -sfR /mnt/ncurses ncurses &&
cd ncurses &&
./configure &&
make -j $CPUS &&
make install &&
cd .. &&
rm -rf ncurses || exit 1

sync
EOF

chmod +x "$WORK"/init || dienow

cd "$TOP"

mksquashfs "$WORK" "$1" -noappend -all-root
