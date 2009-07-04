#!/bin/bash

source sources/include.sh || exit 1

read_arch_dir "$1"

SYSDIR="${BUILD}/system-image-$ARCH_NAME"

if [ ! -f "$SYSDIR/run-emulator.sh" ]
then
  [ -z "$FAIL_QUIET" ] && echo "No $SYSDIR/run-emulator.sh" >&2
  exit 1
fi

cd "$SYSDIR" || exit 1

[ -z "$SKIP_HOME" ] && [ -z "$MAKE_HDB" ] && MAKE_HDB="--make-hdb 2048"

# A little paranoia.
[ -f "image-${ARCH}.ext2" ] && fsck.ext2 -y "image-${ARCH}.ext2" </dev/null

# And run it, using the distccd we built (if necessary) and the cross-compiler.

trap "killtree $$" EXIT

./run-emulator.sh $MAKE_HDB --memory 256 --with-distcc \
	"${BUILD}/cross-compiler-${ARCH}"
