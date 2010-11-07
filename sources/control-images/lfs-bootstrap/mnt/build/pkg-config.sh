#!/bin/sh

sed -i -e 's/XT])dnl/XT])[]dnl/' \
       -e 's/\.])dnl/\.])[]dnl/' pkg.m4 &&
./configure --prefix=/usr &&
make -j $CPUS || exit 1

if [ ! -z "$CHECK" ]
then
  make check || exit 1
fi

make install
