#!/bin/sh

# Portage uses bash ~= regex matches, which were introduced in bash 3.

./configure --enable-cond-regexp --disable-nls --prefix=/usr &&
make -j $CPUS &&
make install
