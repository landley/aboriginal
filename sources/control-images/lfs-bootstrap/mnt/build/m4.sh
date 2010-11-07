#!/bin/sh

sed -i -e '/"m4.h"/a#include <sys/stat.h>' src/path.c &&
./configure --prefix=/usr &&
make || exit 1

if [ ! -z "$CHECK" ]
then
  make check || exit 1
fi

make install
