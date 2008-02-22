#!/tools/bin/bash

# This builds 

# Create some temporary directories at the root level
mkdir -p /{proc,sys,etc,tmp}
[ ! -e /bin ] && ln -s /tools/bin /bin
[ ! -e /lib ] && ln -s /tools/lib /lib

# Populate /dev
mount -t sysfs /sys /sys
mount -t tmpfs /dev /dev
mdev -s

# Setup network for QEMU
mount -t proc /proc /proc
echo "nameserver 10.0.2.3" > /etc/resolv.conf
ifconfig eth0 10.0.2.15
route add default gw 10.0.2.2

# If we have no local clock, you can do this instead:
#rdate time-b.nist.gov

# If there's a /dev/hdb or /dev/sdb, mount it on home

[ -b /dev/hdb ] && HOMEDEV=/dev/hdb
[ -b /dev/sdb ] && HOMEDEV=/dev/hdb
if [ ! -z "$HOMEDEV" ]
then
  mkdir -p /home
  mount $HOMEDEV /home
  export HOME=/home
fi

exec /tools/bin/busybox ash

#wget http://landley.net/hg/firmware/archive/tip.tar.gz
#tar xvzf tip.tar.gz
#cd firmware-*
#./build.sh $ARCH
