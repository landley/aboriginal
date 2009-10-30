#!/bin/bash

# Create hdc image to build dropbear and strace statically.

. sources/include.sh

if [ -z "$1" ]
then
  print "Need directory name" >&2
  exit 1
fi

if [ -e "$1/hdc.sqf" ]
then
  echo "$1/hdc.sqf" exists
  exit 0
fi

# Set up working directories

WORK="$1"
blank_tempdir "$WORK"
WORK="$WORK"/sub
mkdir -p "$WORK" || dienow

# Extract source code into new image directory

setupfor dropbear
setupfor strace

cat > "$WORK"/init << 'EOF' || dienow
#!/bin/bash

echo Started second stage init

cd /home &&
mkdir output &&

echo === Native build static dropbear

cp -sfR /mnt/dropbear dropbear &&
cd dropbear &&
LDFLAGS="--static" ./configure --disable-zlib &&
make -j $CPUS PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" MULTI=1 SCPPROGRESS=1 &&
cp dropbearmulti /home/output &&
cd .. &&
rm -rf dropbear || exit 1

echo === Native build static strace

cp -sfR /mnt/strace strace &&
cd strace &&
CFLAGS="--static" ./configure &&
make -j $CPUS &&
cp strace /home/output &&
cd .. &&
rm -rf strace || dienow

echo === Upload

cd /home/output
for i in *
do
  ftpput 10.0.2.2 -P $OUTPORT $ARCH-$i $i
done

sync

EOF

chmod +x "$WORK"/init || dienow

mksquashfs "$WORK" "$WORK"/../hdc.sqf -noappend -all-root
