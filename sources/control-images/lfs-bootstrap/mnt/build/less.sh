#!/bin/sh

./configure --prefix=/usr --sysconfdir=/etc &&
make -j $CPUS &&
make install
