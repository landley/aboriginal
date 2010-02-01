#!/bin/bash

# Delete all the target stages, to force them to rebuild next build.sh.

# This leaves build.packages and build/host alone.  You can delete those
# too if you like, "rm -rf build" is safe, it just means these steps will have
# to do their thing again:
#
#   EXTRACT_ALL=1 ./download.sh
#   ./host-tools.sh

rm -rf build/*-*
