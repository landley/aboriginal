#!/bin/bash

# Download all the source tarballs we haven't got up-to-date copies of.

# The tarballs are downloaded into the "packages" directory, which is
# created as needed.

source sources/include.sh || exit 1

# Set up working directories

WORK="$BUILD/control-images/hello-world"
blank_tempdir "$WORK"

cat > "$WORK"/init << 'EOF' || dienow
#!/bin/bash

echo Started second stage init

cd /home &&
gcc -lpthread /usr/src/thread-hello2.c -o hello &&
./hello

# Upload our hello world file to the output directory (named hello-$HOST).
# No reason, just an example.

ftpput $FTP_SERVER -P $FTP_PORT hello-$HOST hello

sync

EOF

chmod +x "$WORK"/init || dienow

cd "$TOP"

mksquashfs "$WORK" "$WORK.hdc" -noappend -all-root
