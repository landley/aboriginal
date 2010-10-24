#!/bin/sh

./configure --prefix=/usr --libexecdir=/usr/sbin --localstatedir=/var \
  --disable-logger --disable-syslogd --disable-whois --disable-servers &&
make -j $CPUS &&
make install
