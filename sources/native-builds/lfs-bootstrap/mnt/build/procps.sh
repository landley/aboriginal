#!/bin/sh

sed -i -e 's@\*/module.mk@proc/module.mk ps/module.mk@' Makefile &&
make -j $CPUS &&
make install
