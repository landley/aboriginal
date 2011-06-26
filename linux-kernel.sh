#!/bin/bash

# Package a root filesystem directory into a filesystem image file

source sources/include.sh || exit 1

# Parse sources/targets/$1

load_target "$1"

# If we have an initramfs, incorporate it into the kernel image.

[ -e "$BUILD/root-image-$ARCH/initramfs_data.cpio" ] &&
  MORE_KERNEL_CONFIG="CONFIG_BLK_DEV_INITRD=y\nCONFIG_INITRAMFS_SOURCE=\"$BUILD/root-image-$ARCH/initramfs_data.cpio\"\nCONFIG_INITRAMFS_COMPRESSION_GZIP=y"

# Build linux kernel for the target

setupfor linux
[ -z "$BOOT_KARCH" ] && BOOT_KARCH=$KARCH
make ARCH=$BOOT_KARCH $LINUX_FLAGS KCONFIG_ALLCONFIG=<(getconfig linux && echo -e "$MORE_KERNEL_CONFIG") allnoconfig >/dev/null &&
make -j $CPUS ARCH=$BOOT_KARCH $DO_CROSS $LINUX_FLAGS $VERBOSITY &&
cp "$KERNEL_PATH" "$STAGE_DIR"

cleanup

create_stage_tarball
