#!/bin/sh

./configure --prefix=/usr --bindir=/bin &&
make -j $CPUS || exit 1

if [ ! -z "$CHECK" ]
then
  make check || exit 1
fi

make install
