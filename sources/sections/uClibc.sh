# Install Linux kernel headers.

setupfor linux

# Install Linux kernel headers (for use by uClibc).
make -j $CPUS headers_install ARCH="${KARCH}" INSTALL_HDR_PATH="$STAGE_DIR" &&
# This makes some very old package builds happy.
ln -s ../sys/user.h "$STAGE_DIR/include/asm/page.h"

# Build and install uClibc

make_uClibc()
{
 make -j $CPUS $VERBOSITY CROSS="${ARCH}-" \
  UCLIBC_LDSO_NAME=ld-uClibc KERNEL_HEADERS="$STAGE_DIR/include" \
  PREFIX="$STAGE_DIR/" RUNTIME_PREFIX=/ DEVEL_PREFIX=/ $1 || dienow
}

cleanup

setupfor uClibc

make KCONFIG_ALLCONFIG="$(getconfig uClibc)" allnoconfig &&
cp .config "$WORK/config-uClibc" || dienow

make_uClibc install

# Do we need host or target versions of readelf, ldd, and ldconfig?

if [ ! -z "$HOST_UTILS" ]
then
  make_uClibc hostutils

  for i in $(cd utils; ls *.host | sed 's/\.host//')
  do
    cp utils/"$i".host "$STAGE_DIR/bin/$ARCH-$i" || dienow
  done
else
  make_uClibc install_utils

  # There's no way to specify a prefix for the uClibc utils; rename by hand.

  if [ ! -z "$PROGRAM_PREFIX" ]
  then
    for i in ldd readelf ldconfig
    do
      mv "$STAGE_DIR/bin/"{"$i","${PROGRAM_PREFIX}$i"} || dienow
    done
  fi
fi

cleanup
