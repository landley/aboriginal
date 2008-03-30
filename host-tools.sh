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

# Here are the utilities the build needs that this script doesn't
# build, but which me must instead use from the host system.

# The first seven are from packages already in mini-native.
# The last six need to be added to toybox.  (The build breaks if we use
# the busybox-1.2.2 versions.)

for i in ar as nm cc gcc make ld   bzip2 find install od sort diff
do
  [ ! -f "${HOSTTOOLS}/$i" ] && (ln -s `which $i` "${HOSTTOOLS}/$i" || dienow)
done

# Build toybox
if [ -z "$(which toybox)" ]
then
  setupfor toybox &&
  make defconfig &&
  make install_flat PREFIX="${HOSTTOOLS}" &&
  cd ..

  cleanup toybox
fi

# Yes this is an old version of busybox.  (It's the last version I released
# as busybox maintainer.)  We're gradually replacing busybox with toybox, one
# command at a time.

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
  cd ..

  cleanup busybox
fi

# This is optionally used by mini-native to accelerate native builds when
# running under qemu.  It's not used to build mini-native, or to build
# the cross compiler, but it needs to be on the host system in order to
# use the distcc acceleration trick.

# Build distcc
if [ -z "$(which distcc)" ]
then
  setupfor distcc &&
  ./configure --with-included-popt &&
  make -j "$CPUS" &&
  cp distcc distccd "${HOSTTOOLS}" &&
  cd ..

  cleanup distcc
fi

# As a temporary measure, build User Mode Linux and use _that_ to package
# the ext2 image to boot qemu with.  (Replace this with toybox gene2fs.)

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
  cd ..

  cleanup linux
fi

# Everything after here is stuff we _could_ build, but currently don't.

# Build squashfs
#setupfor squashfs
#cd squashfs-tools &&
#make &&
#cp mksquashfs unsquashfs "${HOSTTOOLS}" &&
#cd ..
#
#cleanup squashfs

# we can't reliably build qemu because it needs a specific gcc version (3.x,
# won't work with 4.x), and who knows what gcc version the host
# has?  So until qemu is fixed to build with an arbitrary c compiler,
# just test for its' existence and warn.  (All the build uses it for is
# a quick sanity test on the cross compiler anyway.)

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
#  cd ..
#
#  cleanup qemu

echo -e "\e[32mHost tools build complete.\e[0m"
