#!/bin/bash

# Download all the source tarballs we haven't got up-to-date copies of.

# The tarballs are downloaded into the "packages" directory, which is
# created as needed.

source sources/include.sh || exit 1

if [ $# -ne 1 ]
then
  echo "usage: $0 FILENAME" >&2
  exit 1
fi

if [ -e "$1" ]
then
  echo "$1" exists
  exit 0
fi

SRCDIR="$SRCDIR/native"
mkdir -p "$SRCDIR" || dienow

echo "=== Download source code."

# Note: set SHA1= blank to skip checksum validation.

URL=http://downloads.sf.net/sourceforge/strace/strace-4.5.19.tar.bz2 \
SHA1=5554c2fd8ffae5c1e2b289b2024aa85a0889c989 \
download || dienow

URL=http://matt.ucc.asn.au/dropbear/releases/dropbear-0.52.tar.bz2 \
SHA1=8c1745a9b64ffae79f28e25c6fe9a8b96cac86d8 \
download || dienow

echo === Got all source.

cleanup_oldfiles

# Set up working directories

WORK="$WORK"/sub
blank_tempdir "$WORK"

# Extract source code into new image directory

setupfor dropbear
setupfor strace

cat > "$WORK"/init << 'EOF' || dienow
#!/bin/bash

upload_result()
{
  ftpput 10.0.2.2 -P $OUTPORT $ARCH-"$1" "$1"
}

echo Started second stage init

echo === Native build static dropbear

cp -sfR /mnt/dropbear dropbear &&
cd dropbear &&
LDFLAGS="--static" ./configure --disable-zlib &&
make -j $CPUS PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" MULTI=1 SCPPROGRESS=1 &&
upload_result dropbearmulti &&
cd .. &&
rm -rf dropbear || exit 1

echo === Native build static strace

cp -sfR /mnt/strace strace &&
cd strace &&
CFLAGS="--static" ./configure &&
make -j $CPUS &&
upload_result strace &&
cd .. &&
rm -rf strace || dienow

sync

EOF

chmod +x "$WORK"/init || dienow

cd "$TOP"

mksquashfs "$WORK" "$1" -noappend -all-root
