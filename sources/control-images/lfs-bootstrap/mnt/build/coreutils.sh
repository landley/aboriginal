#!/bin/sh

./configure --prefix=/usr --enable-no-install-program=kill,uptime &&
make -j $CPUS || exit 1

if [ ! -z "$CHECK" ]
then
  make NON_ROOT_USERNAME=nobody check-root &&
  echo "dummy:x:1000:nobody" >> /etc/group &&
  chown -R nobody . &&
  su-tools nobody -s /bin/bash -c "make RUN_EXPENSIVE_TESTS=yes check" &&
  sed -i '/^dummy:/d' /etc/group || exit 1
fi

make install &&
mv /usr/bin/chroot /usr/sbin
  
