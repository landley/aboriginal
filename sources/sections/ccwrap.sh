# build and install gcc wrapper

# Which compiler do we build the wrapper with, and should it be static?

[ "$BUILD_STATIC" == none ] && STATIC_FLAGS= || STATIC_FLAGS=--static
[ -z "$HOST_ARCH" ] && TEMP="$CC" || TEMP="${HOST_ARCH}-cc"

# Build wrapper binary

"$TEMP" "$SOURCES/toys/ccwrap.c" -Os $CFLAGS \
  -o "$STAGE_DIR/bin/${TOOLCHAIN_PREFIX}cc" $STATIC_FLAGS &&
echo -e '#!/bin/bash\n\ncc -E "$@"' > "$STAGE_DIR/bin/cpp" &&
chmod +x "$STAGE_DIR/bin/cpp" || dienow
