#!/bin/bash

# Package a root filesystem directory into a filesystem image file

source sources/include.sh || exit 1

# Parse sources/targets/$1

load_target "$1"

setupfor linux

# Build linux kernel for the target

getconfig linux > mini.conf
[ "$SYSIMAGE_TYPE" == rootfs ] &&
  echo -e "CONFIG_INITRAMFS_SOURCE=\"$BUILD/rootfs-$ARCH.cpio\"\n" \
    >> mini.conf
make ARCH=${BOOT_KARCH:-$KARCH} $LINUX_FLAGS KCONFIG_ALLCONFIG=mini.conf \
  allnoconfig >/dev/null &&
make -j $CPUS ARCH=${BOOT_KARCH:-$KARCH} $DO_CROSS $LINUX_FLAGS $VERBOSITY &&
cp "$KERNEL_PATH" "$STAGE_DIR"

cleanup

ARCH="$ARCH_NAME" create_stage_tarball
