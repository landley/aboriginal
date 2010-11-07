#!/bin/bash

mkdir build &&
cd build &&
../configure --prefix=/usr --with-root-prefix="" \
  --enable-elf-shlibs --disable-libblkid --disable-libuuid \
  --disable-uuidd --disable-fsck --disable-tls &&
make -j $CPUS || exit 1

if [ ! -z "$CHECK" ]
then
  make check || exit 1
fi

make install &&
make install-libs &&
chmod u+w /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
