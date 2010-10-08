#!/bin/sh

# Need a patch with --dry-run to make portage happy

./configure --prefix=/usr &&
make -j $CPUS &&
make install
