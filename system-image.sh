#!/bin/bash

# Create a bootable system image from mini-native

NO_BASE_ARCH=1
source sources/include.sh

echo -e "$PACKAGE_COLOR"
echo "=== Packaging system image from mini-native"

[ -z "$SYSIMAGE_TYPE" ] && SYSIMAGE_TYPE=ext2

SYSIMAGE="${BUILD}/system-image-${ARCH_NAME}"

TOOLSDIR=tools
[ -z "$NATIVE_TOOLSDIR" ] && TOOLSDIR=usr

# Flush old system-image directory

rm -rf "${SYSIMAGE}"
mkdir -p "${SYSIMAGE}" || dienow

# This next bit is a little complicated; we generate the root filesystem image
# in the middle of building a kernel.  This is necessary to embed an
# initramfs in the kernel, and allows us to parallelize the kernel build with
# the image generation.  Having the other image types in the same if/else
# staircase with initramfs lets us detect unknown image types (probably typos)
# without repeating any.

# Build a linux kernel for the target

setupfor linux
[ -z "$BOOT_KARCH" ] && BOOT_KARCH="$KARCH"
cp "$(getconfig linux)" mini.conf || dienow
[ "$SYSIMAGE_TYPE" == "initramfs" ] &&
  (echo "CONFIG_BLK_DEV_INITRD=y" >> mini.conf || dienow)
make ARCH="${BOOT_KARCH}" KCONFIG_ALLCONFIG=mini.conf \
  allnoconfig >/dev/null || dienow

# Build kernel in parallel with initramfs

( make -j $CPUS ARCH="${BOOT_KARCH}" CROSS_COMPILE="${ARCH}-" $LINUX_FLAGS ||
    dienow ) &

# If we exit before removing this handler, kill everything in the current
# process group, which should take out backgrounded kernel make.
trap "kill 0" EXIT

# Embed an initramfs image in the kernel?

if [ "$SYSIMAGE_TYPE" == "initramfs" ]
then
  echo "Generating initramfs (in background)"
  $CC usr/gen_init_cpio.c -o my_gen_init_cpio || dienow
  (./my_gen_init_cpio <(
      "$SOURCES"/toys/gen_initramfs_list.sh "$NATIVE_ROOT"
      [ ! -e "$NATIVE_ROOT"/init ] &&
        echo "slink /init /$TOOLSDIR/sbin/init.sh 755 0 0"
      [ ! -d "$NATIVE_ROOT"/dev ] && echo "dir /dev 755 0 0"
      echo "nod /dev/console 660 0 0 c 5 1"
    ) || dienow
  ) | gzip -9 > initramfs_data.cpio.gz || dienow
  echo Initramfs generated.

  # Wait for initial kernel build to finish.

  wait4background 0

  # This is a repeat of an earlier make invocation, but if we try to
  # consolidate them the dependencies build unnecessary prereqisites
  # and then decide that they're newer than the cpio.gz we supplied,
  # and thus overwrite it with a default (emptyish) one.

  echo "Building kernel with initramfs."
  [ -f initramfs_data.cpio.gz ] &&
  touch initramfs_data.cpio.gz &&
  mv initramfs_data.cpio.gz usr &&
  make -j $CPUS ARCH="${BOOT_KARCH}" CROSS_COMPILE="${ARCH}-" $LINUX_FLAGS \
    || dienow

  # No need to supply an hda image to emulator.

  IMAGE=
elif [ "$SYSIMAGE_TYPE" == "ext2" ]
then
  # Generate a 64 megabyte ext2 filesystem image from the $NATIVE_ROOT
  # directory, with a temporary file defining the /dev nodes for the new
  # filesystem.

  echo "Generating ext2 image (in background)"

  [ -z "$SYSIMAGE_HDA_MEGS" ] && SYSIMAGE_HDA_MEGS=64

  IMAGE="image-${ARCH}.ext2"
  DEVLIST="$WORK"/devlist

  echo "/dev d 755 0 0 - - - - -" > "$DEVLIST" &&
  echo "/dev/console c 640 0 0 5 1 0 0 -" >> "$DEVLIST" &&

  genext2fs -z -D "$DEVLIST" -d "${NATIVE_ROOT}" \
    -i 1024 -b $[$SYSIMAGE_HDA_MEGS*1024] "${SYSIMAGE}/${IMAGE}" &&
  rm "$DEVLIST" || dienow

#elif [ "$SYSIMAGE_TYPE" == "squashfs" ]
#then
# We used to do this, but updating the squashfs patch for each new kernel
# was just too much work.  If it gets merged someday, we may care again...

#  IMAGE="image-${ARCH}.sqf"
#  echo -n "Creating squashfs image (in background)"
#  "${WORK}/mksquashfs" "${NATIVE_ROOT}" "${SYSIMAGE}/$IMAGE" \
#    -noappend -all-root -info || dienow
else
  echo "Unknown image type." >&2
  dienow
fi

# Wait for kernel build to finish (may be a NOP)

echo Image generation complete.
wait4background 0
trap "" EXIT

# Install kernel

[ -d "${TOOLS}/src" ] && cp .config "${TOOLS}"/src/config-linux
cp "${KERNEL_PATH}" "${SYSIMAGE}/zImage-${ARCH}" &&
cd ..

cleanup linux

# Provide qemu's common command line options between architectures.  The lack
# of ending quotes on -append is intentional, callers append more kernel
# command line arguments and provide their own ending quote.
function qemu_defaults()
{
  if [ "$SYSIMAGE_TYPE" != "initramfs" ]
  then
    HDA="-hda \"$1\" "
    APPEND="root=/dev/$ROOT rw init=/$TOOLSDIR/sbin/init.sh "
  fi

  echo "-nographic -no-reboot -kernel \"$2\" \$WITH_HDB ${HDA}" \
    "-append \"${APPEND}panic=1 PATH=\$DISTCC_PATH_PREFIX/${TOOLSDIR}/bin" \
    "console=$CONSOLE \$KERNEL_EXTRA\" \$QEMU_EXTRA"
}

# Write out a script to call the appropriate emulator.  We split out the
# filesystem, kernel, and base kernel command line arguments in case you want
# to use an emulator other than qemu, but put the default case in qemu_defaults

cp "$SOURCES/toys/run-emulator.sh" "$SYSIMAGE/run-emulator.sh" &&
emulator_command image-$ARCH.ext2 zImage-$ARCH >> "$SYSIMAGE/run-emulator.sh"

[ $? -ne 0 ] && dienow

if [ "$ARCH" == powerpc ]
then
  cp "$SOURCES"/toys/ppc_rom.bin "$SYSIMAGE" || dienow
fi

# Tar it up.

tar -cvj -f "$BUILD"/system-image-$ARCH_NAME.tar.bz2 \
  -C "$BUILD" system-image-$ARCH_NAME || dienow

echo -e "=== Packaging complete\e[0m"
