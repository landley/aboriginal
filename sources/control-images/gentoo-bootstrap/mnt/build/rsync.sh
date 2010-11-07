#!/bin/sh

./configure --prefix=/usr &&
# Break link and touch file, otherwise ./configure tries to recreate it
# which requires perl.
cat proto.h-tstamp > proto.h.new &&
mv -f proto.h.new proto.h-tstamp &&
make -j $CPUS &&
make install
