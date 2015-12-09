#!/bin/bash

# Combine filesystem images, kernel, and emulator launch scripts
# into something you can boot and run.

source sources/include.sh || exit 1

# We do our own dependency checking (like host-tool.sh) so don't delete stage
# dir when parsing sources/targets/$1

KEEP_STAGEDIR=1 load_target "$1"

# Is $1 newer than cross compiler and all listed prerequisites ($2...)?

is_newer()
{
  X="$1"
  shift
  [ ! -e "$X" ] && return 0
  [ "$(which "${CC_PREFIX}cc")" -nt "$X" ] && return 0
  while [ ! -z "$1" ]
  do
    [ ! -z "$(find "$1" -newer "$X" 2>/dev/null)" ] && return 0
    shift
  done

  echo "Keeping $(basename "$X")"
  return 1
}

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

if is_newer "$STAGE_DIR/rootfs.cpio.gz" "$BUILD/root-filesystem-$ARCH"
then
  SYSIMAGE_TYPE=cpio image_filesystem "$BUILD/root-filesystem-$ARCH" \
    "$STAGE_DIR/temp" &&
    mv -f "$STAGE_DIR"/{temp,rootfs}.cpio.gz || dienow
  [ "$SYSIMAGE_TYPE" == rootfs ] && rm -f "$STAGE_DIR/linux"
fi

# Package native-compiler into squashfs for /dev/hda mount

if [ -e "$BUILD/native-compiler-$ARCH" ] &&
  is_newer "$STAGE_DIR/toolchain.sqf" "$BUILD/native-compiler-$ARCH"
then
  SYSIMAGE_TYPE=squashfs image_filesystem "$BUILD/native-compiler-$ARCH" \
    "$STAGE_DIR/temp" &&
    mv -f "$STAGE_DIR"/{temp,toolchain}.sqf || dienow
fi

# Build linux kernel for the target

if is_newer "$STAGE_DIR/linux" "$BUILD/root-filesystem-$ARCH" \
  $(package_cache linux)
then
  setupfor linux
  echo "# make allnoconfig ARCH=${BOOT_KARCH:-$KARCH} KCONFIG_ALLCONFIG=mini.config" \
    > $STAGE_DIR/mini.config
  getconfig linux >> "$STAGE_DIR"/mini.config
  [ "$SYSIMAGE_TYPE" == rootfs ] &&
    echo -e "CONFIG_INITRAMFS_SOURCE=\"$STAGE_DIR/rootfs.cpio.gz\"\n" \
      >> "$STAGE_DIR"/mini.config
  make allnoconfig ARCH=${BOOT_KARCH:-$KARCH} $LINUX_FLAGS \
    KCONFIG_ALLCONFIG="$STAGE_DIR"/mini.config >/dev/null &&
  make -j $CPUS ARCH=${BOOT_KARCH:-$KARCH} $DO_CROSS $LINUX_FLAGS $VERBOSITY &&
  cp "$KERNEL_PATH" "$STAGE_DIR/linux"
  cleanup
fi

# Tar it up.

ARCH="$ARCH_NAME" create_stage_tarball

announce "Packaging complete"
