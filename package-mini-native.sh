#!/bin/bash

# Create an ext2 root filesystem image from mini-native

source sources/include.sh

echo -e "$PACKAGE_COLOR"
echo "=== Packaging system image from mini-native"

SYSIMAGE="${BUILD}/system-image-${ARCH}"
IMAGE="${SYSIMAGE}/image-${ARCH}.ext2"

# Flush old system-image directory

rm -rf "${SYSIMAGE}"
mkdir -p "${SYSIMAGE}" &&

# Generate a 64 megabyte filesystem image from the $NATIVE directory, with a
# temporary file defining the /dev nodes for the new ext2 filesystem.

cat > "$WORK/devlist" << EOF &&
/dev d 755 0 0 - - - - -
/dev/console c 640 0 0 5 1 0 0 -
EOF
mv "$NATIVE/zImage-$ARCH" "$SYSIMAGE" || dienow
genext2fs -z -D "$WORK/devlist" -d "${NATIVE}" -i 1024 -b $[64*1024] "$IMAGE"

# This little dance is because genext2fs hasn't got --exclude so we have to
# move the kernel out of the directory, then hardlink it back.
TEMP=$?
ln "$SYSIMAGE/zImage-$ARCH" "$NATIVE" || dienow
rm "$WORK/devlist" || dienow

[ "$TEMP" -ne 0 ] && dienow

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


