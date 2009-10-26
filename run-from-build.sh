#!/bin/bash

# Grab cross compiler (for distcc) and run development environment.

export PATH="$(pwd)/build/host:$(pwd)/build/cross-compiler-$1/bin:$PATH" &&
cd build/system-image-"$1" &&
./dev-environment.sh
