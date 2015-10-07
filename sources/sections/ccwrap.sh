# build and install gcc wrapper

# Which compiler do we build the wrapper with, and should it be static?

[ "$BUILD_STATIC" == none ] && STATIC_FLAGS= || STATIC_FLAGS=--static
[ -z "$HOST_ARCH" ] && TEMP="$CC" || TEMP="${HOST_ARCH}-cc"
LIBC_TYPE=musl
[ ! -z "$UCLIBC_CONFIG" ] && [ -z "$MUSL" ] && LIBC_TYPE=uClibc

# Build wrapper binary

mkdir -p "$STAGE_DIR/bin" &&
"$TEMP" "$SOURCES/toys/ccwrap.c" -Os $CFLAGS \
  -o "$STAGE_DIR/bin/${TOOLCHAIN_PREFIX}cc" $STATIC_FLAGS \
  -DDYNAMIC_LINKER=\"/lib/ld-${LIBC_TYPE}.so.0\" \
  ${ELF2FLT:+-DELF2FLT} &&
#  ${HOST_ARCH:+${ELF2FLT:+-DELF2FLT}} &&
echo -e "#!/bin/bash\n\n${TOOLCHAIN_PREFIX}cc -E "'"$@"' \
  > "$STAGE_DIR/bin/${TOOLCHAIN_PREFIX}cpp" &&
chmod +x "$STAGE_DIR/bin/${TOOLCHAIN_PREFIX}cpp" || dienow
