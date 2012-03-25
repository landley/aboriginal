#!/bin/bash

# Package a root filesystem directory into a filesystem image file

source sources/include.sh || exit 1

# Parse sources/targets/$1

load_target "$1"

setupfor linux

# Get miniconfig. If we have an initramfs, incorporate it into the kernel image.

getconfig linux > mini.conf
CPIO="$BUILD/root-image-$ARCH/initramfs_data.cpio"
[ -e "$CPIO" ] &&
  echo -e "CONFIG_BLK_DEV_INITRD=y\nCONFIG_INITRAMFS_SOURCE=\"$CPIO\"\nCONFIG_INITRAMFS_COMPRESSION_GZIP=y" >> mini.conf

# Build linux kernel for the target

[ -z "$BOOT_KARCH" ] && BOOT_KARCH=$KARCH
make ARCH=$BOOT_KARCH $LINUX_FLAGS KCONFIG_ALLCONFIG=mini.conf allnoconfig \
  >/dev/null &&
make -j $CPUS ARCH=$BOOT_KARCH $DO_CROSS $LINUX_FLAGS $VERBOSITY &&
cp "$KERNEL_PATH" "$STAGE_DIR"

cleanup

ARCH="$ARCH_NAME" create_stage_tarball
