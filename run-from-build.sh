#!/bin/bash

# Read the configuration files for this target.

source sources/include.sh || exit 1
read_arch_dir "$1"

# Fail if this target hasn't been built yet.

SYSDIR="${BUILD}/system-image-$ARCH_NAME"
if [ ! -f "$SYSDIR/run-emulator.sh" ]
then
  [ -z "$FAIL_QUIET" ] && echo "No $SYSDIR/run-emulator.sh" >&2
  exit 1
fi
cd "$SYSDIR" || exit 1

# Should we create a 2 gigabyte /dev/hdb image to provide the emulator with
# some writable scratch space?  (If one already exists, fsck it.)  This
# image (if it exists) will be mounted on /home by the emulated system's
# init script.

[ -z "$SKIP_HOME" ] && [ -z "$MAKE_HDB" ] && MAKE_HDB="--make-hdb 2048"
[ -f "image-${ARCH}.ext2" ] && fsck.ext2 -y "image-${ARCH}.ext2" </dev/null

# Run the emulator, using the distccd we built (if necessary) to dial out
# to the cross-compiler.  If emulator is killed, take down distccd processes
# as well.

trap "killtree $$" EXIT

./run-emulator.sh $MAKE_HDB --memory 256 --with-distcc \
	"${BUILD}/cross-compiler-${ARCH}"
