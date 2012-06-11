#!/bin/bash

# Combine a root filesystem directory and a control image into an $ARCH-specific
# chroot containing native build control files, suitable for chrooting into.

if [ $# -ne 2 ]
then
  echo "usage: $0 "'$ARCH $CONTROL_IMAGE' >&2
  exit 1
fi

# Make sure prerequisites exist

for i in "build/root-filesystem-$1" "$2"
do
  if [ ! -e "$i" ]
  then
    echo "No $i" >&2
    exit 1
  fi
done

if [ `id -u` -ne 0 ]
then
  echo "Not root">&2
  exit 1
fi

# Zap old stuff (if any)

[ -z "$CHROOT" ] && CHROOT="build/chroot-$1"
trap 'more/zapchroot.sh "$CHROOT"' EXIT
if [ -e "$CHROOT" ]
then
  more/zapchroot.sh "$CHROOT" || exit 1
fi

# Copy root filesystem and splice in control image
cp -a "build/root-filesystem-$1" "$CHROOT" || exit 1

if [ -d "$2" ]
then
  rm -rf "$CHROOT/mnt" && cp -a "$2" "$CHROOT/mnt" || exit 1
else
  mount -o loop "$2" "$CHROOT/mnt" || exit 1
fi

# Output some usage hints

CPUS=1 HOST="$1" chroot "$CHROOT" /sbin/init.sh
