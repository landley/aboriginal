#!/bin/sh

echo '.so man5/modprobe.conf.5' > modprobe.d.5 || exit 1

if [ ! -z "$CHECK" ]
then
  ./configure &&
  make check &&
  ./tests/runtests &&
  make clean || exit 1
fi

./configure --prefix=/ --enable-zlib-dynamic --mandir=/usr/share/man &&
make -j $CPUS &&
make INSTALL=install install
