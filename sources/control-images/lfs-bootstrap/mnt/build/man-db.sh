#!/bin/sh

/configure --prefix=/usr --libexecdir=/usr/lib \
  --docdir=/usr/share/doc/man-db --sysconfdir=/etc --disable-setuid &&
make -j $CPUS || exit 1

if [ ! -z "$CHECK" ]
then
  make check || exit 1
fi

make install
