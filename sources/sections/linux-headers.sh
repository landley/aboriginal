# Install Linux kernel headers.

setupfor linux

# Install Linux kernel headers (for use by uClibc).
make -j $CPUS headers_install ARCH="${KARCH}" INSTALL_HDR_PATH="$STAGE_DIR" &&
# This makes some very old package builds happy.
ln -s ../sys/user.h "$STAGE_DIR/include/asm/page.h"

cleanup
