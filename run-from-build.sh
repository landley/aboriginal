#!/bin/bash

# Grab cross compiler (for distcc) and run development environment.

TOP="$(pwd)"
export PATH="$TOP/build/host:$TOP/build/cross-compiler-$1/bin:$TOP/build/simple-cross-compiler-$1/bin:$PATH"

# Run development environment.

cd build/system-image-"$1" && ./dev-environment.sh
