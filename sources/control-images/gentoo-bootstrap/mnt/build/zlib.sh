#!/bin/sh

# 1.2.5 accidentally shipped the Makefile, then configure tries to
# modify it in place, which fails if the filesystem is read only.
# The fix is to remove it before configuring.

rm Makefile && 
./configure --prefix=/usr &&
make -j $CPUS &&
make install
