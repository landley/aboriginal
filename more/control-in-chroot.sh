#!/bin/bash

# Combine a control image and a root-filesystem image into an $ARCH-specific
# chroot containing native build control files in /mnt.

if [ $# -ne 2 ]
then
  echo 'usage: ./control-in-chroot.sh $ARCH $CONTROL_IMAGE' >&2
  exit 1
fi

# Zap old stuff (if any)

rm -rf build/root-filesystem-"$1" build/chroot-"$1" &&

# Make sure the root filesystem is there for this $ARCH

./root-filesystem.sh "$1" &&

# Build control image.

mkdir -p build/host-temp &&
rm -rf build/host-temp/"$2".hdc &&
sources/native-builds/"$2".sh build/host-temp/"$2".hdc &&

# Combine the control image's files with the root filesystem and rename result.

rm -rf build/control-in-chroot-"$1" build/root-filesystem-"$1"/mnt &&
mv build/host-temp/"$2" build/root-filesystem-"$1"/mnt &&
mv build/root-filesystem-"$1" build/control-in-chroot-"$1" &&

# Tar it up

tar -cvj -f build/control-in-chroot-"$1".tar.bz2 -C build control-in-chroot-"$1" &&

# Output some usage hints

echo "export CPUS=1 HOST=$1 && cd /home && /mnt/init" &&
echo "sudo chroot build/control-in-chroot-"$1" /sbin/init.sh"
