#!/bin/bash

SAVEPATH="$PATH"
source include.sh
PATH="$SAVEPATH"

cd "${BUILD}/system-image-$ARCH" || exit 1

# A little paranoia.
fsck.ext2 -y "image-${ARCH}.ext2" </dev/null

# And run it, using the distccd we built (if necessary) and the cross-compiler.

PATH="$HOSTTOOLS:$PATH" ./run-with-distcc.sh "$CROSS"
