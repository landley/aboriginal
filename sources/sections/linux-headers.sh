# Install Linux kernel headers.

setupfor linux

# This isn't strictly necessary, but if we have a kernel config, expand
# and copy it.

cp "$(getconfig linux)" mini.conf &&
if [ "$SYSIMAGE_TYPE" == "initramfs" ]
then
  echo "CONFIG_BLK_DEV_INITRD=y" >> mini.conf
fi
[ -e mini.conf ] &&
make ARCH=${BOOT_KARCH:-$KARCH} KCONFIG_ALLCONFIG=mini.conf $LINUX_FLAGS \
  allnoconfig >/dev/null &&
cp .config "$STAGE_DIR/config-linux"


# Install Linux kernel headers (for use by uClibc).
make -j $CPUS headers_install ARCH="${KARCH}" INSTALL_HDR_PATH="$STAGE_DIR" &&
# This makes some very old package builds happy.
ln -s ../sys/user.h "$STAGE_DIR/include/asm/page.h"

cleanup

# Remove debris the kernel puts in there for no apparent reason.

find "$STAGE_DIR/include" -name ".install" -print0 -or -name "..install.cmd" -print0 | xargs -0 rm
