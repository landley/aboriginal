#!/bin/bash

# Package a root filesystem directory into a filesystem image, with
# associated bootable kernel binary and launch scripts.

source sources/include.sh || exit 1

# Parse the sources/targets/$1 directory

read_arch_dir "$1"

# Do we have our prerequisites?

[ -z "$NATIVE_ROOT" ] && NATIVE_ROOT="$BUILD/root-filesystem-$ARCH"
if [ ! -d "$NATIVE_ROOT" ]
then
  [ -z "$FAIL_QUIET" ] && echo No "$NATIVE_ROOT" >&2
  exit 1
fi

# Kill our background tasks when we exit prematurely

trap "killtree $$" EXIT

# Announce start of stage.  (Down here after the recursive call above so
# it doesn't get announced twice.)

echo "=== Packaging system image from root-filesystem"

blank_tempdir "$STAGE_DIR"
blank_tempdir "$WORK"

[ -z "$SYSIMAGE_TYPE" ] && SYSIMAGE_TYPE=squashfs

USRDIR=""
[ -z "$ROOT_NODIRS" ] && USRDIR=/usr

# This next bit is a little complicated; we generate the root filesystem image
# in the middle of building a kernel.  This is necessary to embed an
# initramfs in the kernel, and allows us to parallelize the kernel build with
# the image generation.  Having the other image types in the same if/else
# staircase with initramfs lets us detect unknown image types (probably typos)
# without repeating any.

# Build a linux kernel for the target

setupfor linux
[ -z "$BOOT_KARCH" ] && BOOT_KARCH=$KARCH
cp "$(getconfig linux)" mini.conf || dienow
[ "$SYSIMAGE_TYPE" == "initramfs" ] &&
  (echo "CONFIG_BLK_DEV_INITRD=y" >> mini.conf || dienow)
make ARCH=$BOOT_KARCH KCONFIG_ALLCONFIG=mini.conf $LINUX_FLAGS \
  allnoconfig >/dev/null || dienow

# Build kernel in parallel with initramfs

[ ! -e "$STAGE_DIR/zImage-$ARCH" ] &&
  echo "make -j $CPUS ARCH=$BOOT_KARCH $DO_CROSS $LINUX_FLAGS $VERBOSITY" &&
  ( make -j $CPUS ARCH=$BOOT_KARCH $DO_CROSS $LINUX_FLAGS $VERBOSITY ||
    dienow ) &

# Embed an initramfs image in the kernel?

echo "Generating root filesystem of type: $SYSIMAGE_TYPE"

if [ "$SYSIMAGE_TYPE" == "initramfs" ]
then
  $CC usr/gen_init_cpio.c -o my_gen_init_cpio || dienow
  (./my_gen_init_cpio <(
      "$SOURCES"/toys/gen_initramfs_list.sh "$NATIVE_ROOT"
      [ ! -e "$NATIVE_ROOT"/init ] &&
        echo "slink /init $USRDIR/sbin/init.sh 755 0 0"
      [ ! -d "$NATIVE_ROOT"/dev ] && echo "dir /dev 755 0 0"
      echo "nod /dev/console 660 0 0 c 5 1"
    ) || dienow
  ) | gzip -9 > initramfs_data.cpio.gz || dienow
  echo Initramfs generated.

  # Wait for initial kernel build to finish.

  wait

  # This is a repeat of an earlier make invocation, but if we try to
  # consolidate them the dependencies build unnecessary prereqisites
  # and then decide that they're newer than the cpio.gz we supplied,
  # and thus overwrite it with a default (emptyish) one.

  echo "Building kernel with initramfs."
  [ -f initramfs_data.cpio.gz ] &&
  touch initramfs_data.cpio.gz &&
  mv initramfs_data.cpio.gz usr &&
  make -j $CPUS ARCH=$BOOT_KARCH $DO_CROSS $LINUX_FLAGS || dienow

  # No need to supply an hda image to emulator.

  IMAGE=
elif [ "$SYSIMAGE_TYPE" == "ext2" ]
then
  # Generate a 64 megabyte ext2 filesystem image from the $NATIVE_ROOT
  # directory, with a temporary file defining the /dev nodes for the new
  # filesystem.

  [ -z "$SYSIMAGE_HDA_MEGS" ] && SYSIMAGE_HDA_MEGS=64

  IMAGE="image-${ARCH}.ext2"
  DEVLIST="$WORK"/devlist

  echo "/dev d 755 0 0 - - - - -" > "$DEVLIST" &&
  echo "/dev/console c 640 0 0 5 1 0 0 -" >> "$DEVLIST" &&

  # Produce a filesystem with the currently used space plus 20% for filesystem
  # overhead, which should always be big enough.

  BLOCKS=$[1024*(($(du -m -s "$NATIVE_ROOT" | awk '{print $1}')*12)/10)]
  [ $BLOCKS -lt 4096 ] && BLOCKS=4096

  genext2fs -z -D "$DEVLIST" -d "$NATIVE_ROOT" -b $BLOCKS -i 1024 \
    "$STAGE_DIR/$IMAGE" &&
  rm "$DEVLIST" || dienow

  # Extend image size to HDA_MEGS if necessary, keeping it sparse.  (Feeding
  # a larger -b size to genext2fs is insanely slow, and not particularly
  # sparse.)

  if [ $[1024*$SYSIMAGE_HDA_MEGS] -gt 65536 ]
  then
    dd if=/dev/zero of="$STAGE_DIR/$IMAGE" bs=1k count=1 seek=$[1024*1024-1] &&
    resize2fs "$STAGE_DIR/$IMAGE" ${SYSIMAGE_HDA_MEGS}M || dienow
  fi

elif [ "$SYSIMAGE_TYPE" == "squashfs" ]
then
  IMAGE="image-${ARCH}.sqf"
  mksquashfs "${NATIVE_ROOT}" "$STAGE_DIR/$IMAGE" -noappend -all-root \
    -no-progress -p "/dev d 755 0 0" -p "/dev/console c 666 0 0 5 1" || dienow
else
  echo "Unknown image type." >&2
  dienow
fi

# Wait for kernel build to finish (may be a NOP)

echo Image generation complete.
wait
trap "" EXIT

# Install kernel

[ -d "$TOOLS/src" ] && cp .config "$TOOLS/src/config-linux"
cp "$KERNEL_PATH" "$STAGE_DIR/zImage-$ARCH"

cleanup

# Provide qemu's common command line options between architectures.

function kernel_cmdline()
{
  [ "$SYSIMAGE_TYPE" != "initramfs" ] &&
    echo -n "root=/dev/$ROOT rw init=$USRDIR/sbin/init.sh "

  echo -n "panic=1 PATH=\$DISTCC_PATH_PREFIX${USRDIR}/bin console=$CONSOLE"
  echo -n " HOST=$ARCH ${KERNEL_EXTRA}\$KERNEL_EXTRA"
}

function qemu_defaults()
{
  echo -n "-nographic -no-reboot -kernel \"$2\" \$WITH_HDC \$WITH_HDB"
  [ "$SYSIMAGE_TYPE" != "initramfs" ] && echo -n " -hda \"$1\""
  echo -n " -append \"$(kernel_cmdline)\" \$QEMU_EXTRA"
}

# Write out a script to call the appropriate emulator.  We split out the
# filesystem, kernel, and base kernel command line arguments in case you want
# to use an emulator other than qemu, but put the default case in qemu_defaults

cat > "$STAGE_DIR/run-emulator.sh" << EOF || dienow
ARCH=$ARCH
run_emulator()
{
  [ ! -z "\$DEBUG" ] && set -x
  $(emulator_command "$IMAGE" zImage-$ARCH)
}

if [ "\$1" != "--norun" ]
then
  run_emulator
fi
EOF

cat "$SOURCES"/toys/{unique-port,dev-environment}.sh >> "$STAGE_DIR/dev-environment.sh" &&
chmod +x "$STAGE_DIR/dev-environment.sh" || dienow

# Tar it up.

ARCH="$ARCH_NAME" create_stage_tarball

echo -e "=== Packaging complete\e[0m"
