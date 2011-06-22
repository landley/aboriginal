#!/bin/bash

# Download all the source tarballs we haven't got up-to-date copies of.

# The tarballs are downloaded into the "packages" directory, which is
# created as needed.

source sources/include.sh || exit 1

PATCHDIR="$SOURCES/control-images/static-tools-patches"
SRCDIR="$SRCDIR/static-tools" && mkdir -p "$SRCDIR" || dienow
WORK="$BUILD/control-images/static-tools" && blank_tempdir "$WORK"
SRCTREE="$WORK"

EXTRACT_ALL=1

echo "=== Download source code."

# Note: set SHA1= blank to skip checksum validation.

URL=http://downloads.sf.net/sourceforge/strace/strace-4.5.19.tar.bz2 \
SHA1=5554c2fd8ffae5c1e2b289b2024aa85a0889c989 \
maybe_fork download || dienow

URL=http://zlib.net/zlib-1.2.5.tar.bz2 \
SHA1=543fa9abff0442edca308772d6cef85557677e02 \
maybe_fork "download || dienow"

URL=http://matt.ucc.asn.au/dropbear/releases/dropbear-0.53.1.tar.bz2 \
SHA1= \
maybe_fork download || dienow

URL=http://kernel.org/pub/software/utils/pciutils/pciutils-3.1.7.tar.bz2 \
SHA1= \
maybe_fork download || dienow

echo === Got all source.

cleanup_oldfiles

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
sed -i 's@/usr/bin/dbclient@ssh@' options.h &&
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

mksquashfs "$WORK" "$WORK.hdc" -noappend -all-root
