#!/bin/bash

SAVEPATH="$PATH"
source include.sh
PATH="$SAVEPATH"

cd "${BUILD}/system-image-$ARCH" &&
PATH="$HOSTTOOLS:$PATH" ./run-with-distcc.sh "$CROSS"
