#!/bin/bash

SAVEPATH="$PATH"
source sources/include.sh
PATH="$SAVEPATH"

cd "${BUILD}/system-image-$ARCH_NAME" || exit 1

# A little paranoia.
[ -f "image-${ARCH}.ext2" ] && fsck.ext2 -y "image-${ARCH}.ext2" </dev/null

# And run it, using the distccd we built (if necessary) and the cross-compiler.

PATH="$HOSTTOOLS:$PATH" ./run-emulator.sh --make-hdb 2048 --memory 256 \
	--with-distcc "${BUILD}/cross-compiler-${ARCH}"
