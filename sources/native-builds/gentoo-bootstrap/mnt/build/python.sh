#!/bin/sh

./configure --prefix=/usr &&
make -j $CPUS &&
make install
