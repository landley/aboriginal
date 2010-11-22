#!/bin/sh

install -d /lib/firmware /lib/udev/devices/pts /lib/udev/devices/shm &&
mknod -m0666 /lib/udev/devices/null c 1 3 &&
./configure --prefix=/usr --sysconfdir=/etc --sbindir=/sbin \
  --with-rootlibdir=/lib --libexecdir=/lib/udev --disable-extras \
  --disable-introspection &&
make -j $CPUS || exit 1

if [ ! -z "$CHECK" ]
then
  make check || exit 1
fi

make install &&
rmdir /usr/share/doc/udev &&
cd /mnt/packages/udev-config &&
make -j $CPUS install || exit 1

if [ ! -z "$DOCS" ]
then
  make intall-doc
fi
