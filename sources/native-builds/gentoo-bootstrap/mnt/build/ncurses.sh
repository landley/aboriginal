#!/bin/sh

./configure --without-cxx-binding --with-shared &&
make -j $CPUS &&
make install
