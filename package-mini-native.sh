#!/bin/bash

# Create an ext2 root filesystem image
# User User Mode Linux to package this, until toybox mke2fs is ready.

source include.sh

echo -e "$PACKAGE_COLOR"
echo "=== Packaging system image from mini-native"

# We used to do this, but updating the squashfs patch for each new kernel
# was just too much work.  If it gets merged someday, we may care again...

#echo -n "Creating tools.sqf"
#("${WORK}/mksquashfs" "${NATIVE}/tools" "${WORK}/tools.sqf" \
#  -noappend -all-root -info || dienow) | dotprogress

IMAGE="${WORK}/image-${ARCH}.ext2"

# A 64 meg sparse image
rm -f "$IMAGE"
dd if=/dev/zero of="$IMAGE" bs=1024 seek=$[64*1024-1] count=1 &&
/sbin/mke2fs -b 1024 -F "$IMAGE" &&

# If we're not running as root, package via gross hack that needs rewriting.

if [ `id -u` -ne 0 ]
then

# To avoid the need for root access to run this script, build User Mode Linux
# and use _that_ to package the ext2 image to boot qemu with.

if [ ! -f "${HOSTTOOLS}/linux" ]
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

# Recreate tarball if changed.  We need to use tarball produced outside of
# UML because hostfs doesn't detect hard links, which wastes space in the
# resulting filesystem.

cd "$BUILD" || dienow
if [ ! -z "$(find "mini-native-${ARCH}" -newer "mini-native-${ARCH}.tar.bz2")" ]
then
  echo -n updating mini-native-"${ARCH}".tar.bz2 &&
  { tar cjvf "mini-native-${ARCH}.tar.bz2" "mini-native-${ARCH}" || dienow
  } | dotprogress
fi



# Write out a script to control user mode linux
TARDEST="temp-$ARCH"
cat > "${WORK}/uml-package.sh" << EOF &&
#!/bin/sh
mount -n -t ramfs /dev /dev
mknod /dev/loop0 b 7 1
# Jump to build dir
echo -n copying files...
cd "$BUILD"
/sbin/losetup /dev/loop0 "$IMAGE"
mount -n -t ext2 /dev/loop0 "$TARDEST"
cd "$TARDEST"
tar xf "$BUILD/mini-native-${ARCH}.tar.bz2"
mv mini-native-*/* .
rm -rf mini-native-*
mkdir -p dev
mknod dev/console c 5 1
df .
cd ..
umount "$TARDEST"
/sbin/losetup -d /dev/loop0
umount /dev
sync
EOF

chmod +x ${WORK}/uml-package.sh &&

# User Mode Linux refuses to run if it detects its input has run out, so
# running this script < /dev/null won't work, nor will piping the output
# of echo into this.  It prints out a page or so worth of whatever we feed
# into it, so script < /dev/null is out too.  If we feed it known garbage
# and try to filter it out with grep -v afterwards, it gets chopped at
# a page boundary and some garbage gets output anyway.  If we feed it data
# from a process that blocks, never supplying EOF but never supplying input
# either, the first process doesn't know when to exit.  This is a compromise
# workaround, which looks like a progress indicator but isn't really.
(while echo -n "."; do sleep 1; done) |
"${HOSTTOOLS}/linux" rootfstype=hostfs rw quiet ARCH=${ARCH} \
    PATH=/bin:/usr/bin:/sbin:/usr/sbin init="${HOSTTOOLS}/oneit -p \
    ${WORK}/uml-package.sh" || dienow

# If we're running as root, we don't need UML.

else
  TARDEST="$BUILD/temp-$ARCH"
  mount -o loop "$IMAGE" "$TARDEST" &&
  cp -a "$BUILD/mini-native-${ARCH}"/. "$TARDEST" &&
  mkdir -p "$TARDEST"/dev &&
  mknod "$TARDEST"/dev/console c 5 1 &&
  df "$TARDEST"

  RETVAL=$?

  umount -d "$TARDEST"

  [ "$RETVAL" -eq 0 ] || dienow
fi

# Provide qemu's common command line options between architectures.  The lack
# of ending quotes on -append is intentional, callers append more kernel
# command line arguments and provide their own ending quote.
function qemu_defaults()
{
  echo "-nographic -no-reboot \$WITH_HDB" \
       "-hda \"$1\" -kernel \"$2\"" \
       "-append \"root=/dev/$ROOT console=$CONSOLE" \
       "rw init=/tools/bin/qemu-setup.sh panic=1" \
       'PATH=$DISTCC_PATH_PREFIX/tools/bin $KERNEL_EXTRA"'
}

# Call the appropriate emulator.  We split out the filesystem, kernel, and
# base kernel command line arguments in case you want to use an emulator
# other than qemu, but put the default case in QEMU_BASE.

emulator_command image-$ARCH.ext2 zImage-$ARCH > "$WORK/run-emulator.sh" &&

chmod +x "$WORK/run-emulator.sh"

# Create system-image-$ARCH.tar.bz2

function shipit()
{
  cd "$BUILD" || dienow
  rm -rf system-image-$ARCH
  mkdir system-image-$ARCH &&
  ln "$WORK"/{image-$ARCH.ext2,zImage-$ARCH,run-*.sh} system-image-$ARCH &&
  cp "$SOURCES"/toys/run-with-{distcc,home}.sh system-image-$ARCH

  [ $? -ne 0 ] && dienow

  if [ ! -z "$NATIVE_NOTOOLSDIR" ]
  then
    sed -i 's@/tools/@/usr/@g' "system-image-$ARCH"/*.sh || dienow
  fi

  [ "$ARCH" == powerpc ] && cp "$SOURCES"/toys/ppc_rom.bin system-image-$ARCH
  tar cvjf "$BUILD"/system-image-$ARCH.tar.bz2 system-image-$ARCH
}

shipit
echo -e "=== Packaging complete\e[0m"
