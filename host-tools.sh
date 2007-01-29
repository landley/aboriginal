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

# Build qemu (if it's not already installed)

TEMP="qemu-${QEMU_TEST}"
[ -z "$QEMU_TEST" ] && TEMP=qemu

if [ -z "$(which $TEMP)" ]
then

  setupfor qemu &&
  ./configure --disable-gcc-check --disable-gfx-check --prefix="${CROSS}" &&
  make &&
  make install &&
  cd .. &&
  $CLEANUP qemu-*

  [ $? -ne 0 ] && dienow
fi

echo -e "\e[32mHost tools build complete.\e[0m"
