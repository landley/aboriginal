#!/bin/bash

# Get lots of predefined environment variables and shell functions.

# Tell bash not to memorize the path to anything, so toybox utilities get
# used immediately even if a different executable was found last $PATH lookup.
set +h

echo -e "\e[0m"
echo "=== Building host tools"

NO_ARCH=1
source include.sh

mkdir -p "${HOSTTOOLS}" || dienow

# Build busybox
if [ -z "$(which busybox)" ]
then
  setupfor busybox &&
  cp "${SOURCES}/config-busybox" .config &&
  yes "" | make oldconfig &&
  make &&
  cp busybox "${HOSTTOOLS}"

  [ $? -ne 0 ] && dienow

  for i in $(sed 's@.*/@@' busybox.links)
  do
    ln -s busybox "${HOSTTOOLS}"/$i || dienow
  done
  cd .. &&
  $CLEANUP busybox

  [ $? -ne 0 ] && dienow
fi

# Build toybox
if [ -z "$(which toybox)" ]
then
  setupfor toybox &&
  make defconfig &&
  make &&
  make instlist &&
  make install_flat PREFIX="${HOSTTOOLS}" &&
  cd .. &&
  $CLEANUP toybox

  [ $? -ne 0 ] && dienow
fi

# Build distcc
if [ -z "$(which distcc)" ]
then
  setupfor distcc &&
  ./configure --with-included-popt &&
  make -j "$CPUS" &&
  cp distcc distccd "${HOSTTOOLS}" &&
  cd .. &&
  $CLEANUP distcc

  [ $? -ne 0 ] && dienow
fi

# As a temporary measure, build User Mode Linux and use _that_ to package
# the ext2 image to boot qemu with.

if [ -z "$(which linux)" ]
then
  setupfor linux &&
  cat > mini.conf << EOF &&
CONFIG_BINFMT_ELF=y
CONFIG_HOSTFS=y
CONFIG_LBD=y
CONFIG_BLK_DEV=y
CONFIG_BLK_DEV_LOOP=y
CONFIG_STDERR_CONSOLE=y
CONFIG_UNIX98_PTYS=y
CONFIG_EXT2_FS=y
EOF
  make ARCH=um allnoconfig KCONFIG_ALLCONFIG=mini.conf &&
  make -j "$CPUS" ARCH=um &&
  cp linux "${HOSTTOOLS}" &&
  cd .. &&
  $CLEANUP linux

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

# we can't reliably build qemu because who knows what gcc version the host
# has?  so until qemu is fixed to build with an arbitrary c compiler,
# just test for its' existence and warn.

temp="qemu-${qemu_test}"
[ -z "$qemu_test" ] && temp=qemu

if [ -z "$(which $temp)" ]
then
  echo "***************** warning: $temp not found. *******************"
fi

#  setupfor qemu &&
#  ./configure --disable-gcc-check --disable-gfx-check --prefix="${CROSS}" &&
#  make &&
#  make install &&
#  cd .. &&
#  $CLEANUP qemu-*

for i in ar as bzip2 cc cp find gcc install ld make nm od sort
do
  rm -f "${HOSTTOOLS}/$i"
  ln -sf `which $i` "${HOSTTOOLS}/$i" || dienow
done

echo -e "\e[32mHost tools build complete.\e[0m"
