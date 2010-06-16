#!/bin/bash

# Run the busybox test suite.

source sources/include.sh || exit 1

[ $# -ne 1 ] && echo "usage: $0 FILENAME" >&2 && exit 1
[ -e "$1" ] && echo "$1" exists && exit 0

WORK="$WORK"/busybox-test && blank_tempdir "$WORK"

# Don't download busybox, it's got to already be there in standard sources.

setupfor busybox
cd "$TOP"

cat > "$WORK"/init << 'EOF' || dienow
#!/bin/bash

echo === $HOST Run busybox test suite

cp -sfR /mnt/busybox busybox && cd busybox &&
make defconfig &&
ln -s /bin/busybox busybox &&
cd testsuite &&
./runtest &&
cd .. &&
rm -rf busybox || exit 1

sync

EOF

chmod +x "$WORK"/init || dienow

mksquashfs "$WORK" "$1" -noappend -all-root
