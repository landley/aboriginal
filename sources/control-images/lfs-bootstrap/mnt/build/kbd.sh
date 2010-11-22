#!/bin/sh

./configure --prefix=/usr --datadir=/lib/kbd --disable-nls &&
make -j $CPUS &&
make install || exit 1

if [ ! -z "$DOCS" ]
then
  mkdir /usr/share/doc/kbd &&
  cp -R doc/* /usr/share/doc/kbd
fi
