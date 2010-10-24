#!/bin/sh

./configure --prefix=/usr &&
echo '#define YYENABLE_NLS 1' >> lib/config.h &&
make -j $CPUS || exit 1

if [ ! -z "$CHECK" ]
then
  make check || exit 1
fi

make install
