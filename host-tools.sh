#!/bin/sh

# Get lots of predefined environment variables and shell functions.

echo -e "\e[0m"
echo "=== Building host tools"

NO_ARCH=1
source include.sh

#rm -rf "${HOSTTOOLS}"
mkdir -p "${HOSTTOOLS}" || dienow

# Build toybox
if [ ! -f "$(which toybox)" ]
then
echo which toybox
  setupfor toybox &&
  make defconfig &&
  make &&
  make instlist &&
  make install_flat PREFIX="${HOSTTOOLS}"

  [ $? -ne 0 ] && dienow
fi

# As a temporary measure, build User Mode Linux and use _that_ to package
# the ext2 image to boot qemu with.

if [ -z "$(which linux)" ]
then
  setupfor linux &&
  cat > mini.conf << EOF
CONFIG_MODE_SKAS=y
CONFIG_BINFMT_ELF=y
CONFIG_HOSTFS=y
CONFIG_SYSCTL=y
CONFIG_STDERR_CONSOLE=y
CONFIG_UNIX98_PTYS=y
CONFIG_BLK_DEV_LOOP=y
CONFIG_LBD=y
CONFIG_EXT2_FS=y
CONFIG_PROC_FS=y
EOF
  make ARCH=um allnoconfig KCONFIG_ALLCONFIG=mini.conf &&
  make ARCH=um &&
  cp linux "${HOSTTOOLS}" &&
  cd .. &&
  rm -rf linux-*

  [ $? -ne 0 ] && dienow
fi

# Build squashfs
#setupfor squashfs
#cd squashfs-tools &&
#make &&
#cp mksquashfs unsquashfs "${HOSTTOOLS}" &&
#cd .. &&
#$CLEANUP squashfs*
#
#[ $? -ne 0 ] && dienow

# Build qemu (if it's not already installed)

TEMP="qemu-${QEMU_TEST}"
[ -z "$QEMU_TEST" ] && TEMP=qemu

if [ -z "$(which $TEMP)" ]
then

  setupfor qemu &&
  ./configure --disable-gcc-check --disable-gfx-check --prefix="${CROSS}" &&
  make &&
  make install &&
  cd .. &&
  $CLEANUP qemu-*

  [ $? -ne 0 ] && dienow
fi

echo -e "\e[32mHost tools build complete.\e[0m"
