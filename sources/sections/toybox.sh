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
