#!/bin/bash

# Launch system image out of build directory.

cd build/system-image-"$1" && ./run-emulator.sh
