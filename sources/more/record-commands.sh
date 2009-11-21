#!/bin/bash

source sources/include.sh || exit 1

# Build a wrapper that records each command line the build runs out of the
# host's $PATH, so we know exactly what commands the build uses.

# (Note: this misses things called via absolute paths, such as the #!/bin/bash
# at the start of shell scripts.)

echo "=== Setting up command recording wrapper"

PATH="$OLDPATH"
blank_tempdir "$WRAPDIR"
blank_tempdir "$BUILD/logs"

# Populate a directory of symlinks with every command in the $PATH.

# For each each $PATH element, loop through each file in that directory,
# and create a symlink to the wrapper with that name.  In the case of
# duplicates, keep the first one.

echo "$PATH" | sed 's/:/\n/g' | while read i
do
  ls -1 "$i" | while read j
  do
    ln -s wrappy "$WRAPDIR/$j" 2>/dev/null
  done
done

# Build the wrapper
$CC -Os "$SOURCES/toys/wrappy.c" -o "$WRAPDIR/wrappy"  || dienow
