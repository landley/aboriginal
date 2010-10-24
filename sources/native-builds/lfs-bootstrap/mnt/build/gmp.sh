#!/bin/sh

# Doesn't work with uClibc++ yet.
# [ ! -z "$(which c++)" ] && X="--enable-cxx"

./configure --prefix=/usr $X --enable-mpbsd &&
make -j $CPUS || exit 1

if [ ! -z "$CHECK" ]
then
  make check 2>&1 | tee gmp-check-log
  awk '/tests passed/{total+=$2} ; END{print total}' gmp-check-log
fi

make install || exit 1

if [ ! -z "$DOCS" ]
then
  mkdir -p /usr/share/doc/gmp-5.0.1 &&
  cp doc/isa_abi_headache doc/connfiguration doc/*.html \
    /usr/share/doc/gmp-5.0.1
fi
