#!/bin/bash

# Create an ext2 root filesystem image
# User User Mode Linux to package this, until toybox mke2fs is ready.

source include.sh

#echo -n "Creating tools.sqf"
#("${WORK}/mksquashfs" "${NATIVE}/tools" "${WORK}/tools.sqf" \
#  -noappend -all-root -info || dienow) | dotprogress

IMAGE="${WORK}/image-${ARCH}.ext2"

# A 64 meg sparse image
rm -f "$IMAGE"
dd if=/dev/zero of="$IMAGE" bs=1024 seek=$[64*1024-1] count=1 &&
/sbin/mke2fs -b 1024 -F "$IMAGE" &&

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
TARDEST="mini-native-$ARCH"
tar c
cat > "${WORK}/uml-package.sh" << EOF &&
#!/bin/sh
mount -n -t ramfs /dev /dev
mknod /dev/loop0 b 7 1
# Jump to build dir
echo copying files...
cd "$BUILD"
/sbin/losetup /dev/loop0 "$IMAGE"
mount -n -t ext2 /dev/loop0 "$TARDEST"
tar xf "$BUILD/mini-native-${ARCH}.tar.bz2"
mkdir "$TARDEST"/dev
mknod "$TARDEST"/dev/console c 5 1
df "$TARDEST"
umount "$TARDEST"
/sbin/losetup -d /dev/loop0
umount /dev
sync
EOF
chmod +x ${WORK}/uml-package.sh &&
linux rootfstype=hostfs rw quiet ARCH=${ARCH} PATH=/bin:/usr/bin:/sbin:/usr/sbin init="${HOSTTOOLS}/oneit -p ${WORK}/uml-package.sh"

# Call the appropriate emulator

emulator_command image-$ARCH.ext2 zImage-$ARCH \
  'rw init=/tools/bin/qemu-setup.sh panic=1 PATH=$DISTCC_PATH_PREFIX/tools/bin $DISTCC_VARS' \
  > "$WORK/run-emulator.sh" &&

chmod +x "$WORK/run-emulator.sh"

# Create qemu-image-$ARCH.tar.bz2

function shipit()
{
  cd "$WORK" &&
  mkdir qemu-image-$ARCH &&
  ln {image-$ARCH.ext2,zImage-$ARCH,run-*.sh} \
	"$SOURCES"/toys/run-with-{distcc,home}.sh \
	qemu-image-$ARCH &&

  [ $? -ne 0 ] && dienow

  [ "$ARCH" == powerpc ] && ln "$SOURCES"/toys/ppc_rom.bin qemu-image-$ARCH
  tar cvjf "$BUILD"/qemu-image-$ARCH.tar.bz2 qemu-image-$ARCH &&
  rm -rf qemu-image-$ARCH
}

shipit
