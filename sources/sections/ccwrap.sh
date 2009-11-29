# build and install gcc wrapper script.

# Which compiler do we build the wrapper with?

TEMP="${FROM_ARCH}-cc"
[ -z "$FROM_ARCH" ] && TEMP="$CC" || LIBTYPE="-DGIMME_AN_S"

# Copy compiler binaries (if not already present)

if [ ! -e "$STAGE_DIR/bin/${PROGRAM_PREFIX}"rawcc ]
then
  # Populate the wrapper directories (unfinished)

  mkdir -p "$STAGE_DIR"/{tools,include,lib,cc/{include,lib}} &&

  # Setup bin directory

  mkdir -p "$STAGE_DIR/bin" || dienow
  path_search "$PATH" "${PROGRAM_PREFIX}*" \
    'cp "$DIR/$FILE" "$STAGE_DIR/bin/$FILE"' | dot_progress

  mv "$STAGE_DIR/bin/${PROGRAM_PREFIX}"{cc,rawcc} ||
  mv "$STAGE_DIR/bin/${PROGRAM_PREFIX}"{gcc,rawcc} || dienow
  ln -sf "${PROGRAM_PREFIX}cc" "$STAGE_DIR/bin/${PROGRAM_PREFIX}gcc" || dienow

  # populate include

  SYSINC_PATH="$(echo '#include <stdio.h>' | "$ARCH-cc" -E - | \
    sed -n 's@.*"\(.*\)/stdio\.h".*@\1@p;T;q')"

  # populate lib

    # Need both /lib and /usr/lib.  What if libc.so linker script points to
    # other directory?  --print-search-dirs, perhaps?

  # populate cc/include

  # This is the trick uClibc build uses.

  CCINC_PATH="$(gcc --print-file-name=include)"

  # populate cc/lib

  CCLIB_PATH="$(gcc --print-file-name=crtbegin.o | sed 's@crtbegin.o$@@')"
  # or maybe --print-search-dirs "libraries"?

  # Populate tools
fi

# Build wrapper binary

"$TEMP" "$SOURCES/toys/ccwrap.c" -Os -s \
  -o "$STAGE_DIR/bin/${PROGRAM_PREFIX}cc" $LIBTYPE $STATIC_FLAGS \
  -DGCC_UNWRAPPED_NAME='"'"${PROGRAM_PREFIX}rawcc"'"' || dienow

# PACKAGE=gcc cleanup build-gcc "${STAGE_DIR}"/{lib/gcc,{libexec/gcc,gcc/lib}/install-tools,bin/${ARCH}-unknown-*}
