#!/bin/bash

# Download all the source tarballs we haven't got up-to-date copies of.

# The tarballs are downloaded into the "packages" directory, which is
# created as needed.

source sources/include.sh || exit 1

[ $# -ne 1 ] && echo "usage: $0 FILENAME" >&2 && exit 1
[ -e "$1" ] && echo "$1" exists && exit 0

PATCHDIR="$SOURCES/native-builds/static-tools-patches"
ls $PATCHDIR
SRCDIR="$SRCDIR/native" && mkdir -p "$SRCDIR" || dienow
WORK="$WORK"/static-tools && blank_tempdir "$WORK"

echo "=== Download source code."

# Note: set SHA1= blank to skip checksum validation.

URL=http://downloads.sf.net/sourceforge/strace/strace-4.5.19.tar.bz2 \
SHA1=5554c2fd8ffae5c1e2b289b2024aa85a0889c989 \
maybe_fork download || dienow

URL=http://zlib.net/zlib-1.2.5.tar.bz2 \
SHA1=543fa9abff0442edca308772d6cef85557677e02 \
maybe_fork "download || dienow"

URL=http://matt.ucc.asn.au/dropbear/releases/dropbear-0.52.tar.bz2 \
SHA1=8c1745a9b64ffae79f28e25c6fe9a8b96cac86d8 \
maybe_fork download || dienow

echo === Got all source.

cleanup_oldfiles

setupfor strace
setupfor zlib
setupfor dropbear

cat > "$WORK"/init << 'EOF' || dienow
#!/bin/bash

upload_result()
{
  ftpput $FTP_SERVER -P $FTP_PORT "$1-$HOST" "$1"
}

echo Started second stage init

echo === Native build static zlib

cp -sfR /mnt/zlib zlib &&
cd zlib &&
# 
rm -f Makefile &&
./configure &&
make -j $CPUS &&
cd .. || exit 1

echo === $HOST Native build static dropbear

cp -sfR /mnt/dropbear dropbear &&
cd dropbear &&
CFLAGS="-I ../zlib -Os" LDFLAGS="--static -L ../zlib" ./configure &&
make -j $CPUS PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" MULTI=1 SCPPROGRESS=1 &&
strip dropbearmulti &&
upload_result dropbearmulti &&
cd .. &&
rm -rf dropbear || exit 1

echo === $HOST native build static strace

cp -sfR /mnt/strace strace &&
cd strace &&
CFLAGS="--static -Os" ./configure &&
make -j $CPUS &&
strip strace &&
upload_result strace &&
cd .. &&
rm -rf strace || dienow

echo === $HOST native build rsync

sync

EOF

chmod +x "$WORK"/init || dienow

cd "$TOP"

mksquashfs "$WORK" "$1" -noappend -all-root
