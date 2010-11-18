#!/bin/sh

./configure --prefix=/usr --docdir=/usr/share/doc/automake &&
make -j $CPUS || exit 1

if [ ! -z "$CHECK" ]
then
  make check || exit 1
fi

make install
