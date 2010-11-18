#!/bin/sh

./configure --prefix=/usr --bindir=/bin --htmldir=/usr/share/doc/sed &&
make -j $CPUS || exit 1

if [ ! -z "$DOCS" ]
then
  make html &&
  make -C doc install-html || exit 1
fi

if [ ! -z "$CHECK" ]
then
  make check || exit 1
fi

make install
