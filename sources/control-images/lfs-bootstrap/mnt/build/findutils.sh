#!/bin/sh

./configure --prefix=/usr --libexecdir=/usr/lib/findutils \
  --localstatedir=/var/lib/locate &&
make -j $CPUS || exit 1

if [ ! -z "$CHECK" ]
then
  make check || exit 1
fi

make install
