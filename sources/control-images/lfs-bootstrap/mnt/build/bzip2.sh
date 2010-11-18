#!/bin/sh

# Use relative paths when installing symlinks, not absolute paths.
sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile &&

# The extra song and dance is to install the shared library, and
# make the bzip2 binary use it.

make -f Makefile-libbz2_so &&
make clean &&
make &&
make PREFIX=/usr install &&
cp bzip2-shared /bin/bzip2 &&
cp -a libbz2.so* /lib
