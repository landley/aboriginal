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

# Set up working directories

WORK="$WORK"/sub
blank_tempdir "$WORK"

cat > "$WORK"/init << 'EOF' || dienow
#!/bin/bash

echo Started second stage init

cd /home &&
gcc -lpthread /usr/src/thread-hello2.c -o hello &&
./hello

sync

EOF

chmod +x "$WORK"/init || dienow

cd "$TOP"

mksquashfs "$WORK" "$1" -noappend -all-root
