#!/bin/bash

# Download all the source tarballs we haven't got up-to-date copies of.

# The tarballs are downloaded into the "packages" directory, which is
# created as needed.

source sources/include.sh || exit 1

[ $# -ne 1 ] && echo "usage: $0 FILENAME" >&2 && exit 1
[ -e "$1" ] && echo "$1" exists && exit 0

SRCDIR="$SRCDIR/native" && mkdir -p "$SRCDIR" || dienow
WORK="$WORK"/sub && blank_tempdir "$WORK"

echo "=== Download source code."

# Note: set SHA1= blank to skip checksum validation.

URL=http://downloads.sf.net/sourceforge/strace/strace-4.5.19.tar.bz2 \
SHA1=5554c2fd8ffae5c1e2b289b2024aa85a0889c989 \
download || dienow
setupfor strace

URL=http://zlib.net/zlib-1.2.4.tar.bz2 \
SHA1=8cf10521c1927daa5e12efc5e1725a0d70e579f3 \
maybe_fork "download || dienow"
setupfor zlib

URL=http://matt.ucc.asn.au/dropbear/releases/dropbear-0.52.tar.bz2 \
SHA1=8c1745a9b64ffae79f28e25c6fe9a8b96cac86d8 \
download || dienow
setupfor dropbear

echo === Got all source.

cleanup_oldfiles

cat > "$WORK"/init << 'EOF' || dienow
#!/bin/bash

upload_result()
{
  ftpput 10.0.2.2 -P $OUTPORT "$1-$ARCH" "$1"
}

echo Started second stage init

echo === Native build static zlib

cp -sfR /mnt/zlib zlib &&
cd zlib &&
./configure &&
make -j $CPUS &&
cd .. || exit 1

echo === $ARCH Native build static dropbear

cp -sfR /mnt/dropbear dropbear &&
cd dropbear &&
CFLAGS="-I ../zlib -Os" LDFLAGS="--static -L ../zlib" ./configure &&
make -j $CPUS PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" MULTI=1 SCPPROGRESS=1 &&
strip dropbearmulti &&
upload_result dropbearmulti &&
cd .. &&
rm -rf dropbear || exit 1

echo === $ARCH Native build static strace

cp -sfR /mnt/strace strace &&
cd strace &&
CFLAGS="--static -Os" ./configure &&
make -j $CPUS &&
strip strace &&
upload_result strace &&
cd .. &&
rm -rf strace || dienow

sync

EOF

chmod +x "$WORK"/init || dienow

cd "$TOP"

mksquashfs "$WORK" "$1" -noappend -all-root
