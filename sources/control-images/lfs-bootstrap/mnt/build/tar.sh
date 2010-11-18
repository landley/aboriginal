#!/bin/sh

sed -i /SIGPIPE/d src/tar.c &&
./configure --prefix=/usr --bindir=/bin --libexecdir=/usr/sbin &&
make -j $CPUS || exit 1

if [ ! -z "$CHECK" ]
then
  sed -i '35 i AT_UNPRIVILEGED_PREREQ' tests/remfiles01.at &&
  make check || exit 1
fi

make install
