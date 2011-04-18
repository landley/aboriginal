#!/bin/bash

# Combine a filesystem image and kernel with emulator launch scripts.

source sources/include.sh || exit 1

# Parse the sources/targets/$1 directory

read_arch_dir "$1"

cd "$BUILD/linux-kernel-$ARCH_NAME" &&
KERNEL="$(ls)" &&
ln "$KERNEL" "$STAGE_DIR" &&
cd "$BUILD/root-image-$ARCH" &&
IMAGE="$(ls)" &&
ln "$IMAGE" "$STAGE_DIR" || dienow

# Provide qemu's common command line options between architectures.

kernel_cmdline()
{
  [ "$SYSIMAGE_TYPE" != "initramfs" ] &&
    echo -n "root=/dev/$ROOT rw init=/sbin/init.sh "

  echo -n "panic=1 PATH=\$DISTCC_PATH_PREFIX/bin:/sbin console=$CONSOLE"
  echo -n " HOST=$ARCH ${KERNEL_EXTRA}\$KERNEL_EXTRA"
}

qemu_defaults()
{
  echo -n "-nographic -no-reboot -kernel $KERNEL \$WITH_HDC \$WITH_HDB"
  [ "$SYSIMAGE_TYPE" != "initramfs" ] && echo -n " -hda $IMAGE"
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
  $(emulator_command)
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
