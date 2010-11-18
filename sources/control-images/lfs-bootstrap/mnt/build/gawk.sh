#!/bin/sh

./configure --prefix=/usr --libexecdir=/usr/lib &&
make -j $CPUS || exit 1

if [ ! -z "$CHECK" ]
then
  make check || exit 1
fi

make install || exit 1

if [ ! -z "$DOCS" ]
then
  mkdir /usr/share/doc/gawk &&
  cp doc/awkforai.txt doc/*.eps doc/*.pdf doc/*.jpg /usr/share/doc/gawk
fi
