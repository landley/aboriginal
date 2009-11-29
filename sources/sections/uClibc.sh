# Build and install uClibc

make_uClibc()
{
 make -j $CPUS $VERBOSITY CROSS="${ARCH}-" \
  UCLIBC_LDSO_NAME=ld-uClibc KERNEL_HEADERS="$STAGE_DIR/include" \
  PREFIX="$STAGE_DIR/" RUNTIME_PREFIX=/ DEVEL_PREFIX=/ $1 || dienow
}

setupfor uClibc

if unstable uClibc && [ -e "$CONFIG_DIR/$ARCH/miniconfig-alt-uClibc" ]
then
  cp "$CONFIG_DIR/$ARCH/miniconfig-alt-uClibc" "$WORK/mini.conf" || dienow
  echo using miniconfig-alt-uClibc
else
  cp "$SOURCES/baseconfig-uClibc" "$WORK/mini.conf" &&
  echo "$UCLIBC_CONFIG" >> "$WORK/mini.conf" || dienow
  echo Creating miniconfig for uClibc
fi
make KCONFIG_ALLCONFIG="$WORK/mini.conf" allnoconfig &&
cp .config "$WORK/config-uClibc" || dienow

make_uClibc install

if [ -d "$ROOT_TOPDIR/src" ]
then
  cp "${WORK}/config-uClibc" "$ROOT_TOPDIR/src/config-uClibc" || dienow
fi

# Do we need host or target versions of ldd and such?

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
    mv "${STAGE_DIR}"/{sbin,bin}/ldconfig || dienow
    for i in ldd readelf ldconfig
    do
      mv "$STAGE_DIR/bin/"{"$i","${PROGRAM_PREFIX}$i"}
    done
  fi
fi

cleanup
