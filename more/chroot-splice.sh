#!/bin/bash

# Combine a root filesystem directory and a control image into an $ARCH-specific
# chroot containing native build control files, suitable for chrooting into.

if [ $# -ne 2 ]
then
  echo 'usage: ./control-in-chroot.sh $ARCH $CONTROL_IMAGE' >&2
  exit 1
fi

# Make sure prerequisites exist

for i in "build/root-filesystem-$1" "$2"
do
  if [ ! -d "$i" ]
  then
    echo "No $i" >&2
    exit 1
  fi
done

# Zap old stuff (if any)

if [ -e "build/chroot-$1-$2" ]
then
  more/zapchroot.sh "build/chroot-$1-$2" &&
  rm -rf "build/chroot-$1-$2" ||
    exit 1
fi

# Copy root filesystem and splice in control image
cp -la "build/root-filesystem-$1" "build/chroot-$1-$2" &&
cp -la "$2/." "build/chroot-$1-$2/mnt/." ||
  exit 1

# Tar it up

# Output some usage hints

echo "export CPUS=1 HOST=$1 && cd /home && /mnt/init" &&
echo "sudo chroot build/chroot-$1-$2" "/sbin/init.sh"
