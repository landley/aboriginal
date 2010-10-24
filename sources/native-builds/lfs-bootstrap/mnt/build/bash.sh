#!/bin/sh

./configure --prefix=/usr --bindir=/bin --htmldir=/usr/share/doc/bash \
  --without-bash-malloc --with-installed-readline &&
make -j $CPUS || exit 1

if [ ! -z "$CHECK" ]
then
  chown -R nobody . &&
  su-tools nobody -s /bin/bash -c "make tests" || exit 1
fi

make install
