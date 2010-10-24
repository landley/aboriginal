#!/bin/sh

sed -k '/MV.*old/d' Makefile.in &&
sed -i '/{OLDSUFF}/c:' support/shlib-install &&
./configure --prefix=/usr --libdir=/lib &&
make -j $CPUS SHLIB_LIBS=-lncurses &&
make install  || exit 1

if [ ! -z "$DOCS" ]
then
  mkdir /usr/share/doc/readline &&
  install -m644 doc/*.ps doc/*.pdf doc/*.html doc/*.dvi \
    /usr/share/doc/readline
fi
