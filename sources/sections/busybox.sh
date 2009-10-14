#!/bin/bash

[ ! -z "$ARCH" ] && DO_CROSS=CROSS_COMPILE=${ARCH}-

# Build busybox

setupfor busybox
make allyesconfig KCONFIG_ALLCONFIG="${SOURCES}/trimconfig-busybox" &&
cp .config "$WORK"/config-busybox
LDFLAGS="$LDFLAGS $STATIC_FLAGS" make -j $CPUS $VERBOSITY $DO_CROSS &&
make busybox.links &&
cp busybox "${STAGE_DIR}"

[ $? -ne 0 ] && dienow

for i in $(sed 's@.*/@@' busybox.links)
do
  [ ! -f "${STAGE_DIR}/$i" ] &&
    (ln -sf busybox "${STAGE_DIR}/$i" || dienow)
done

cleanup

# Build toybox

[ ! -z "$ARCH" ] && DO_CROSS=CROSS_COMPILE=${ARCH}-

setupfor toybox
make defconfig &&
CFLAGS="$CFLAGS $STATIC_FLAGS" make $DO_CROSS || dienow
if [ -z "$USE_TOYBOX" ]
then
  mv toybox "$STAGE_DIR" &&
  ln -sf toybox "$STAGE_DIR"/patch &&
  ln -sf toybox "$STAGE_DIR"/oneit &&
  ln -sf toybox "$STAGE_DIR"/netcat || dienow
else
  make install_flat PREFIX="$STAGE_DIR" || dienow
fi

cleanup
