#!/bin/bash

# Run the busybox test suite.

source sources/include.sh || exit 1

WORK="$BUILD/control-images/busybox-test" && blank_tempdir "$WORK"

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

mksquashfs "$WORK" "$WORK.hdc" -noappend -all-root
