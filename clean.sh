#!/bin/bash

# Delete all the target stages, to force them to rebuild next build.sh.

# This leaves build.packages and build/host alone.  (You can delete those
# too if you like, rm -rf build is safe, it just means ./download.sh --extract
# and ./host-tools.sh will have to do their thing again, which takes a while.)

rm -rf build/*-*
