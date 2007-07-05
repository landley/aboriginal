#!/tools/bin/bash

# This builds 

# Create some temporary directories at the root level
mkdir -p /{proc,sys,etc}
ln -s /tools/bin /bin
ln -s /tools/lib /lib

# Populate /dev
mount -t sysfs /sys /sys
mdev -s

# Setup network for QEMU
mount -t proc /proc /proc
echo "nameserver 10.0.2.3" > /etc/resolv.conf
ifconfig eth0 10.0.2.15
route add default gw 10.0.2.2
rdate time-b.nist.gov

exec /tools/bin/busybox ash

#wget http://landley.net/hg/firmware/archive/tip.tar.gz
#tar xvzf tip.tar.gz
#cd firmware-*
#./build.sh $ARCH
