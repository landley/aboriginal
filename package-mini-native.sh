#!/bin/bash

# Create an ext2 root filesystem image from mini-native

source sources/include.sh

echo -e "$PACKAGE_COLOR"
echo "=== Packaging system image from mini-native"

SYSIMAGE="${BUILD}/system-image-${ARCH}"
IMAGE="${SYSIMAGE}/image-${ARCH}.ext2"

# Flush old system-image directory

rm -rf "${SYSIMAGE}"
mkdir -p "${SYSIMAGE}" || dienow

# Build a linux kernel for the target

setupfor linux
make ARCH="${KARCH}" KCONFIG_ALLCONFIG="$(getconfig linux)" allnoconfig &&
make -j $CPUS ARCH="${KARCH}" CROSS_COMPILE="${ARCH}-" || dienow

# Embed an initramfs image?

if [ ! -z "USE_INITRAMFS" ]
then
  /bin/bash scripts/gen_initramfs_list.sh -u $(id -u) -g $(id -g) \
    "$NATIVE" > initramfs.txt
  [ ! -d "$NATIVE"/dir ] && echo "dir /dev 0755 0 0" >> initramfs.txt
  echo "nod /dev/console 0640 0 0 c 5 1" >> initramfs.txt

  make ARCH="${KARCH}" CROSS_COMPILE="${ARCH}-" \
    CONFIG_INITRAMFS_SOURCE=initramfs.txt || dienow
fi

# Install kernel

[ -d "${TOOLS}/src" ] && cp .config "${TOOLS}"/src/config-linux
cp "${KERNEL_PATH}" "${SYSIMAGE}/zImage-${ARCH}" &&
cd ..

cleanup linux

if [ -z "$USE_INITRAMFS" ]
then
  # Generate a 64 megabyte ext2 filesystem image from the $NATIVE directory,
  # with a temporary file defining the /dev nodes for the new filesystem.

  cat > "$WORK/devlist" << EOF &&
/dev d 755 0 0 - - - - -
/dev/console c 640 0 0 5 1 0 0 -
EOF
  genext2fs -z -D "$WORK/devlist" -d "${NATIVE}" -i 1024 -b $[64*1024] \
    "$IMAGE" &&
  rm "$WORK/devlist" || dienow
fi

# Provide qemu's common command line options between architectures.  The lack
# of ending quotes on -append is intentional, callers append more kernel
# command line arguments and provide their own ending quote.
function qemu_defaults()
{
  echo -n "-nographic -no-reboot \$WITH_HDB"
  [ -z "$USE_INITRAMFS" ] && echo -n " -hda \"$1\""
  echo " -kernel \"$2\" -append \"root=/dev/$ROOT console=$CONSOLE" \
       "rw init=/tools/bin/qemu-setup.sh panic=1" \
       'PATH=$DISTCC_PATH_PREFIX/tools/bin $KERNEL_EXTRA"'
}

# Write out a script to call the appropriate emulator.  We split out the
# filesystem, kernel, and base kernel command line arguments in case you want
# to use an emulator other than qemu, but put the default case in qemu_defaults

cp "$SOURCES/toys/run-emulator.sh" "$SYSIMAGE/run-emulator.sh" &&
emulator_command image-$ARCH.ext2 zImage-$ARCH >> "$SYSIMAGE/run-emulator.sh"

[ $? -ne 0 ] && dienow

# Adjust things before creating tarball.

if [ -z "$NATIVE_TOOLSDIR" ]
then
  sed -i 's@/tools/@/usr/@g' "$SYSIMAGE/run-emulator.sh" || dienow
fi

if [ "$ARCH" == powerpc ]
then
  cp "$SOURCES"/toys/ppc_rom.bin "$SYSIMAGE" || dienow
fi

# Tar it up.

tar -cvj -f "$BUILD"/system-image-$ARCH.tar.bz2 \
  -C "$BUILD" system-image-$ARCH || dienow

echo -e "=== Packaging complete\e[0m"


# We used to do this, but updating the squashfs patch for each new kernel
# was just too much work.  If it gets merged someday, we may care again...

#echo -n "Creating tools.sqf"
#("${WORK}/mksquashfs" "${NATIVE}/tools" "${WORK}/tools.sqf" \
#  -noappend -all-root -info || dienow) | dotprogress


