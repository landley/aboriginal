#!/bin/sh

# zlib 1.2.5 accidentally shipped a generated file, which it then tries to
# overwrite in-place.  This doesn't work so well on a read only filesystem.

rm -f Makefile &&

# Fix another bug.

sed -i 's/ifdef _LARGEFILE64_SOURCE/ifndef _LARGEFILE64_SOURCE/' zlib.h &&

# Otherwise, standard build

./configure --prefix=/usr &&
make -j $CPUS || exit 1

if [ ! -z "$CHECK" ]
then
  make check || exit 1
fi

make install
