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

PATCHDIR="$SOURCES/native-builds/gentoo-stage1-patches"
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
maybe_fork download || dienow

URL=http://ftp.gnu.org/gnu/bash/bash-3.2.tar.gz \
SHA1=fe6466c7ee98061e044dae0347ca5d1a8eab4a0d \
maybe_fork download || dienow 

echo === Got all source.

cleanup_oldfiles

# The reason this is isn't grouped together with the downloads above is when
# you download a new version but haven't deleted the old one yet, setupfor
# gets confused.

setupfor zlib
setupfor ncurses
setupfor Python
setupfor bash

cat > "$WORK"/init << 'EOF' || dienow
#!/bin/bash

upload_result()
{
  ftpput $FTP_SERVER -P $FTP_PORT "$1-$HOST" "$1"
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
  mkdir gentoo-stage1
  find / -xdev | cpio -m -v -p /home/gentoo-stage1 | dotprogress

  echo Restarting init script in chroot
  for i in mnt proc sys dev; do mount --bind /$i gentoo-stage1/$i; done
  chroot gentoo-stage1 /mnt/init
  RC=$?
  for i in mnt proc sys dev; do umount gentoo-stage1/$i; done


  if [ $RC -eq 0 ]
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

set_titlebar "Python"

cp -sfR /mnt/Python python &&
cd python &&
./configure &&
make -j $CPUS &&
make install &&
cd .. &&
rm -rf python || exit 1

# Portage uses bash ~= regex matches, which were introduced in bash 3.

set_titlebar "Bash3"

cp -sfR /mnt/bash bash &&
cd bash &&
./configure --enable-cond-regexp --disable-nls &&
make -j $CPUS &&
make install &&
cd .. &&
rm -rf bash || exit 1

EOF

chmod +x "$WORK"/init || dienow

cd "$TOP"

mksquashfs "$WORK" "$1" -noappend -all-root
