#!/bin/sh

sed -e 's@etc/adjtime@var/lib/hwclock/adjtime@g' \
  -i $(grep -rl '/etc/adjtime' .) &&
mkdir -p /var/lib/hwclock &&
./configure --enable-arch --enable-partx --enable-write &&
make -j $CPUS &&
make install
