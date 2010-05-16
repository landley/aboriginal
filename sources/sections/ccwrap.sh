# build and install gcc wrapper script.

# Which compiler do we build the wrapper with, and should it be static?

if [ -z "$FROM_ARCH" ] || [ "$BUILD_STATIC" == none ]
then
  TEMP="$CC"
  STATIC_FLAGS=
else
  TEMP="${FROM_ARCH}-cc"
  STATIC_FLAGS=--static
fi

# Copy compiler binaries (if not already present)

if false
then
  # Populate the wrapper directories (unfinished)

  # The purpose of this is to wrap an existing cross compiler by populating
  # a directory of symlinks in the layout ccwrap expects.  This requires
  # querying the existing compiler to find 1) system header dirs,
  # 2) compiler header dirs, 3) system library dirs, 4) compiler library dirs,
  # 5) binary search path for cpp and ld and such.

  mkdir -p "$STAGE_DIR"/{tools,include,lib,cc/{include,lib}} &&

  # Setup bin directory

  mkdir -p "$STAGE_DIR/bin" || dienow
  path_search "$PATH" "${PROGRAM_PREFIX}*" \
    'cp "$DIR/$FILE" "$STAGE_DIR/bin/$FILE"' | dotprogress

  mv "$STAGE_DIR/"{bin/"${PROGRAM_PREFIX}"cc,tools/bin/cc} ||
  mv "$STAGE_DIR/"{bin/"${PROGRAM_PREFIX}"gcc,tools/bin/cc} || dienow
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

"$TEMP" "$SOURCES/toys/ccwrap.c" -Os $CFLAGS \
  -o "$STAGE_DIR/bin/${PROGRAM_PREFIX}cc" $STATIC_FLAGS || dienow
