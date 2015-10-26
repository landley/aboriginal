# This pile of crap cannot be built without zlib. Even if you're not using
# it, neither the autoconf nor the C has any concept of _not_ using zlib.

setupfor zlib
CC=${HOST_ARCH:+${HOST_ARCH}-}$CC ./configure &&
make -j $CPUS &&
install -D z*.h "$STAGE_DIR/host/include" &&
install -D libz.a "$STAGE_DIR/host/lib" &&
cleanup

setupfor elf2flt
CC=${HOST_ARCH:+${HOST_ARCH}-}$CC CFLAGS="$CFLAGS $STATIC_FLAGS" \
  ./configure --with-bfd-include-dir="$STAGE_DIR/host/include" \
  --with-binutils-include-dir="$STAGE_DIR/host/include" \
  --with-libiberty="$STAGE_DIR/host/lib/libiberty.a" --prefix="$STAGE_DIR" \
  --with-libbfd="$STAGE_DIR/host/lib/libbfd.a" --target="$ELF2FLT" \
  --with-zlib-prefix="$STAGE_DIR/host" --enable-always-reloc-text \
  ${HOST_ARCH:+--host=${KARCH}-unknown-linux} &&
make -j $CPUS &&
make install TARGET="$CROSS_TARGET" PREFIX="$TOOLCHAIN_PREFIX"

[ $? -ne 0 ] && dienow

# elf2flt's wrapper sometimes calls the unprefixed version of this. :(

if [ ! -e "$STAGE_DIR/bin/ld.real" ]
then
  ln -s "${TOOLCHAIN_PREFIX}ld.real" "$STAGE_DIR/bin/ld.real"
fi

cleanup
