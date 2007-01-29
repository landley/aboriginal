#!/bin/sh

# Get lots of predefined environment variables and shell functions.

echo -e "\e[0m"
echo "=== Building host tools"

source include.sh

mkdir -p "${CROSS}/bin" || dienow

# Build squashfs
setupfor squashfs
cd squashfs-tools &&
make &&
cp mksquashfs unsquashfs "${CROSS}/bin" &&
cd .. &&
$CLEANUP squashfs*

[ $? -ne 0 ] && dienow

# Build qemu

[ -z "$QEMU_TEST" ] || QEMU_BUILD_TARGET="${QEMU_TEST}-user"

setupfor qemu &&
./configure --disable-gcc-check --disable-gfx-check \
  --target-list="${KARCH}-softmmu $QEMU_BUILD_TARGET" --prefix="${CROSS}" &&
make &&
make install &&
cd .. &&
$CLEANUP qemu-*

[ $? -ne 0 ] && dienow

echo -e "\e[32mHost tools build complete.\e[0m"
