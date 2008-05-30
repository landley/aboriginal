#!/bin/bash

source include.sh

cd "${BUILD}/system-image-$ARCH" &&
PATH="$HOSTTOOLS:$PATH" ./run-with-distcc.sh "$CROSS"
