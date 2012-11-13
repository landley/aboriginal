#!/bin/bash

source sources/include.sh || exit 1

# Build a wrapper that records each command line the build runs out of the
# host's $PATH, so we know exactly what commands the build uses.

# (Note: this misses things called via absolute paths, such as the #!/bin/bash
# at the start of shell scripts.)

echo "=== Setting up command recording wrapper"

[ -f "$WRAPDIR/wrappy" ] && PATH="$OLDPATH"
[ -f "$HOSTTOOLS/toybox" ] && PATH="$(hosttools_path)"
blank_tempdir "$WRAPDIR"

# Populate a directory of symlinks with every command in the $PATH.

path_search "$PATH" "*" 'ln -s wrappy "$WRAPDIR/$FILE"' | dotprogress

# Build the wrapper
$CC -Os "$SOURCES/toys/wrappy.c" -o "$WRAPDIR/wrappy"  || dienow
