#!/bin/bash

# Combine a filesystem image and kernel with emulator launch scripts.

# Package a root filesystem directory into a filesystem image file

source sources/include.sh || exit 1

# Parse sources/targets/$1

load_target "$1"

# Provide qemu's common command line options between architectures.

qemu_defaults()
{
  echo -n "-nographic -no-reboot -kernel linux"
  [ "$SYSIMAGE_TYPE" != "rootfs" ] && echo -n " -initrd rootfs.cpio.gz"
  echo -n " -append \"panic=1 console=$CONSOLE HOST=$ARCH \$KERNEL_EXTRA\""
  echo -n " \$QEMU_EXTRA"
}

# Write out a script to call the appropriate emulator.  We split out the
# filesystem, kernel, and base kernel command line arguments in case you want
# to use an emulator other than qemu, but put the default case in qemu_defaults

cat > "$STAGE_DIR/run-emulator.sh" << EOF &&
#!/bin/bash

# Boot the emulated system to a shell prompt.

ARCH=$ARCH
run_emulator()
{
  [ ! -z "\$DEBUG" ] && set -x
  $(emulator_command)
}

if [ "\$1" != "--norun" ]
then
  run_emulator
fi
EOF
chmod +x "$STAGE_DIR/run-emulator.sh" &&

# Write out development wrapper scripts, substituting INCLUDE lines.

for FILE in dev-environment.sh native-build.sh
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

# Package root-filesystem into cpio file for initramfs

SYSIMAGE_TYPE=cpio image_filesystem "$BUILD/root-filesystem-$ARCH" \
  "$STAGE_DIR/rootfs" &&
if [ -d "$BUILD/native-compiler-$ARCH" ]
then
  SYSIMAGE_TYPE=squashfs image_filesystem "$BUILD/native-compiler-$ARCH" \
    "$STAGE_DIR/toolchain" || dienow
fi

# Build linux kernel for the target

if [ -z "$NO_CLEANUP" ] || [ ! -e "$STAGE_DIR/linux" ]
then
  setupfor linux
  getconfig linux > mini.conf
  [ "$SYSIMAGE_TYPE" == rootfs ] &&
    echo -e "CONFIG_INITRAMFS_SOURCE=\"$BUILD/root-filesystem-$ARCH/rootfs.cpio.gz\"\n" \
      >> mini.conf
  make ARCH=${BOOT_KARCH:-$KARCH} $LINUX_FLAGS KCONFIG_ALLCONFIG=mini.conf \
    allnoconfig >/dev/null &&
  make -j $CPUS ARCH=${BOOT_KARCH:-$KARCH} $DO_CROSS $LINUX_FLAGS $VERBOSITY &&
  cp "$KERNEL_PATH" "$STAGE_DIR/linux"
  cleanup
fi
# Tar it up.

ARCH="$ARCH_NAME" create_stage_tarball

announce "Packaging complete"
