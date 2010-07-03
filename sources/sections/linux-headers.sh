# Install Linux kernel headers.

setupfor linux

# Expand and copy kernel .config.

getconfig linux > mini.conf &&
[ "$SYSIMAGE_TYPE" == "initramfs" ] &&
echo "CONFIG_BLK_DEV_INITRD=y" >> mini.conf

make ARCH=${BOOT_KARCH:-$KARCH} KCONFIG_ALLCONFIG=mini.conf $LINUX_FLAGS \
  allnoconfig >/dev/null &&
mkdir -p "$STAGE_DIR/src" &&
cp .config "$STAGE_DIR/src/config-linux"


# Install Linux kernel headers (for use by uClibc).
make -j $CPUS headers_install ARCH="${KARCH}" INSTALL_HDR_PATH="$STAGE_DIR" &&
# This makes some very old package builds happy.
ln -s ../sys/user.h "$STAGE_DIR/include/asm/page.h"

cleanup

# Remove debris the kernel puts in there for no apparent reason.

find "$STAGE_DIR/include" -name ".install" -print0 -or -name "..install.cmd" -print0 | xargs -0 rm
