#!/bin/bash

# Calculate new config for UNSTABLE kernel based on stable kernel config.
# I.E. calculate miniconfig-alt-linux based on miniconfig-linux for a target.

# Expand miniconfig with the old kernel, copy .config to new kernel, run
# make oldconfig, compress to miniconfig, copy to sources/targets/$TARGET

. sources/include.sh

read_arch_dir "$1"

blank_tempdir "$WORK"

[ -z "$BOOT_KARCH" ] && BOOT_KARCH="$KARCH"

# Expand config against current kernel

USE_UNSTABLE=

setupfor linux

cp "$(getconfig linux)" mini.conf || dienow
[ "$SYSIMAGE_TYPE" == "initramfs" ] &&
  (echo "CONFIG_BLK_DEV_INITRD=y" >> mini.conf || dienow)
make ARCH="$BOOT_KARCH" KCONFIG_ALLCONFIG=mini.conf $LINUX_FLAGS \
  allnoconfig > /dev/null &&
cp .config "$WORK"

cleanup

USE_UNSTABLE=linux

setupfor linux

cp "$WORK/.config" . &&
yes "" | make ARCH="$BOOT_KARCH" oldconfig &&
mv .config walrus &&
ARCH="${BOOT_KARCH}" "$SOURCES/toys/miniconfig.sh" walrus || dienow

CFG="$CONFIG_DIR/$ARCH_NAME/miniconfig-alt-linux"
if [ -e "$CFG" ] && ! cmp mini.config "$CFG"
then
  mv "$CFG" "${CFG}.bak" || dienow
fi
mv mini.config "$CFG"

cleanup
