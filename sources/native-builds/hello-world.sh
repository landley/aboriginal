#!/bin/bash

# Download all the source tarballs we haven't got up-to-date copies of.

# The tarballs are downloaded into the "packages" directory, which is
# created as needed.

source sources/include.sh || exit 1

[ $# -ne 1 ] && echo "usage: $0 FILENAME" >&2 && exit 1
[ -e "$1" ] && echo "$1 exists" && exit 0

# Set up working directories

WORK="$WORK"/sub
blank_tempdir "$WORK"

cat > "$WORK"/init << 'EOF' || dienow
#!/bin/bash

echo Started second stage init

cd /home &&
gcc -lpthread /usr/src/thread-hello2.c -o hello &&
./hello

# Upload our hello world file to the output directory (named hello-$ARCH).
# No reason, just an example.

ftpput 10.0.2.2 -P $OUTPORT hello-"$ARCH" hello

sync

EOF

chmod +x "$WORK"/init || dienow

cd "$TOP"

mksquashfs "$WORK" "$1" -noappend -all-root
