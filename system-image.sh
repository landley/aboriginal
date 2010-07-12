#!/bin/bash

# Package a root filesystem directory into a filesystem image, with
# associated bootable kernel binary and launch scripts.

source sources/include.sh || exit 1

# Parse the sources/targets/$1 directory

read_arch_dir "$1"

# Do we have our prerequisites?

if [ -z "$NATIVE_ROOT" ]
then
  [ -z "$NO_NATIVE_COMPILER" ] &&
    NATIVE_ROOT="$BUILD/root-filesystem-$ARCH" ||
    NATIVE_ROOT="$BUILD/simple-root-filesystem-$ARCH"
fi

if [ ! -d "$NATIVE_ROOT" ]
then
  [ -z "$FAIL_QUIET" ] && echo No "$NATIVE_ROOT" >&2
  exit 1
fi

# Announce start of stage.  (Down here after the recursive call above so
# it doesn't get announced twice.)

echo "=== Packaging system image from root-filesystem"

mkdir -p "$STAGE_DIR"
blank_tempdir "$WORK"

# The initramfs packaging uses the kernels build infrastructure, so extract
# it now.

setupfor linux

[ -z "$SYSIMAGE_TYPE" ] && SYSIMAGE_TYPE=squashfs
echo "Generating $SYSIMAGE_TYPE root filesystem from $NATIVE_ROOT."

# Embed an initramfs image in the kernel?

if [ "$SYSIMAGE_TYPE" == "initramfs" ]
then
  $CC usr/gen_init_cpio.c -o my_gen_init_cpio || dienow
  ./my_gen_init_cpio <(
      "$SOURCES"/toys/gen_initramfs_list.sh "$NATIVE_ROOT" || dienow
      [ ! -e "$NATIVE_ROOT"/init ] &&
        echo "slink /init /sbin/init.sh 755 0 0"
      [ ! -d "$NATIVE_ROOT"/dev ] && echo "dir /dev 755 0 0"
      echo "nod /dev/console 660 0 0 c 5 1"
    ) > initramfs_data.cpio || dienow
  echo Initramfs generated.

  # No need to supply an hda image to the emulator.

  IMAGE=

  MORE_KERNEL_CONFIG='CONFIG_BLK_DEV_INITRD=y\nCONFIG_INITRAMFS_SOURCE="initramfs_data.cpio"\nCONFIG_INITRAMFS_COMPRESSION_GZIP=y'

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

  echo "$(stat -c %s "$STAGE_DIR/$IMAGE") -lt $SYSIMAGE_HDA_MEGS"

  if [ ! -z "$SYSIMAGE_HDA_MEGS" ] &&
     [ $((`stat -c %s "$STAGE_DIR/$IMAGE"` / (1024*1024) )) -lt "$SYSIMAGE_HDA_MEGS" ]
  then
    echo resizing image to $SYSIMAGE_HDA_MEGS
    dd if=/dev/zero of="$STAGE_DIR/$IMAGE" bs=1k count=1 seek=$[1024*1024-1] &&
    resize2fs "$STAGE_DIR/$IMAGE" ${SYSIMAGE_HDA_MEGS}M || dienow
    echo resize complete
  fi

elif [ "$SYSIMAGE_TYPE" == "squashfs" ]
then
  IMAGE="image-${ARCH}.sqf"
  mksquashfs "${NATIVE_ROOT}" "$STAGE_DIR/$IMAGE" -noappend -all-root \
    ${FORK:+-no-progress} -p "/dev d 755 0 0" \
    -p "/dev/console c 666 0 0 5 1" || dienow
else
  echo "Unknown image type." >&2
  dienow
fi

echo Image generation complete.

# Build linux kernel for the target

[ -z "$BOOT_KARCH" ] && BOOT_KARCH=$KARCH
make ARCH=$BOOT_KARCH $LINUX_FLAGS KCONFIG_ALLCONFIG=<(getconfig linux && echo -e "$MORE_KERNEL_CONFIG") allnoconfig >/dev/null &&
make -j $CPUS ARCH=$BOOT_KARCH $DO_CROSS $LINUX_FLAGS $VERBOSITY &&
cp "$KERNEL_PATH" "$STAGE_DIR/zImage-$ARCH"

cleanup

# Provide qemu's common command line options between architectures.

kernel_cmdline()
{
  [ "$SYSIMAGE_TYPE" != "initramfs" ] &&
    echo -n "root=/dev/$ROOT rw init=/sbin/init.sh "

  echo -n "panic=1 PATH=\$DISTCC_PATH_PREFIX/bin console=$CONSOLE"
  echo -n " HOST=$ARCH ${KERNEL_EXTRA}\$KERNEL_EXTRA"
}

qemu_defaults()
{
  echo -n "-nographic -no-reboot -kernel \"$2\" \$WITH_HDC \$WITH_HDB"
  [ "$SYSIMAGE_TYPE" != "initramfs" ] && echo -n " -hda \"$1\""
  echo -n " -append \"$(kernel_cmdline)\" \$QEMU_EXTRA"
}

# Write out a script to call the appropriate emulator.  We split out the
# filesystem, kernel, and base kernel command line arguments in case you want
# to use an emulator other than qemu, but put the default case in qemu_defaults

cat > "$STAGE_DIR/run-emulator.sh" << EOF &&
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
chmod +x "$STAGE_DIR/run-emulator.sh" &&

# Write out development wrapper scripts, substituting INCLUDE lines.

[ -z "$NO_NATIVE_COMPILER" ] && for FILE in dev-environment.sh native-build.sh
do
  (export IFS="$(echo -e "\n")"
   cat "$SOURCES/toys/$FILE" | while read -r i
   do
     if [ "${i:0:8}" == "INCLUDE " ]
     then
       cat "$SOURCES/toys/${i:8}" || dienow
     else
       # because echo doesn't support --, that's why.
       echo "$i" || dienow
     fi
   done
  ) > "$STAGE_DIR/$FILE"

  chmod +x "$STAGE_DIR/$FILE" || dienow
done

# Tar it up.

ARCH="$ARCH_NAME" create_stage_tarball

echo "=== Packaging complete"
