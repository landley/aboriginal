#!/bin/sh

# TODO: The --enable-thread-safe here requires TLS

./configure --prefix=/usr --docdir=/usr/share/doc/mpfr-3.0.0 &&
make -j $CPUS || exit 1

if [ ! -z "$CHECK" ]
then
  make check || exit 1
fi

make install || exit 1

if [ ! -z "$DOCS" ]
then
  make html &&
  make install-html
fi
