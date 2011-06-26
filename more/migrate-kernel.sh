#!/bin/bash

# Calculate new config for UNSTABLE kernel based on stable kernel config.
# I.E. calculate miniconfig-alt-linux based on miniconfig-linux for a target.

# Expand miniconfig with the old kernel, copy .config to new kernel, run
# make oldconfig, compress to miniconfig, copy to sources/targets/$TARGET

. sources/include.sh

load_target "$1"
rmdir "$STAGE_DIR"

[ -z "$BOOT_KARCH" ] && BOOT_KARCH="$KARCH"

# Expand config against current kernel

USE_UNSTABLE=

getconfig linux > "$WORK/miniconfig-linux"

setupfor linux

make ARCH=$BOOT_KARCH $LINUX_FLAGS KCONFIG_ALLCONFIG="$WORK/miniconfig-linux" \
  allnoconfig >/dev/null &&
cp .config "$WORK"

cleanup

USE_UNSTABLE=linux

setupfor linux

mv "$WORK/.config" . &&
yes "" | make ARCH="$BOOT_KARCH" oldconfig &&
mv .config walrus &&
ARCH="${BOOT_KARCH}" "$SOURCES/toys/miniconfig.sh" walrus || dienow

CFG="$CONFIG_DIR/$ARCH_NAME/miniconfig-alt-linux"
if [ -e "$CFG" ] && ! cmp mini.config "$CFG"
then
  mv "$CFG" "${CFG}.bak" || dienow
fi
mv mini.config "$CFG"

cleanup

diff -u <(sort "$WORK/miniconfig-linux") <(sort "$CFG") \
 | sed '/^ /d;/^@/d;1,2d' | tee "$WORK/mini.diff"
