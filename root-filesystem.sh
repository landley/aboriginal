#!/bin/bash

# Build a root filesystem for a given target.

source sources/include.sh || exit 1
read_arch_dir "$1"
check_for_base_arch || exit 0
check_prerequisite "${ARCH}-cc"

# Announce start of stage.

echo "=== Building $STAGE_NAME"

# Determine which directory layout we're using

if [ -z "$ROOT_NODIRS" ]
then
  mkdir -p "$STAGE_DIR"/{tmp,proc,sys,dev,home,mnt} &&
  chmod a+rwxt "$STAGE_DIR/tmp" || dienow
  for i in bin sbin lib etc
  do
    mkdir -p "$STAGE_DIR/usr/$i" &&
    ln -s "usr/$i" "$STAGE_DIR/$i" || dienow
  done

  STAGE_DIR="$STAGE_DIR/usr"
else
  mkdir -p "$STAGE_DIR/bin" || dienow
fi

# Copy qemu setup script and so on.

cp -r "${SOURCES}/native-root/." "$STAGE_DIR/" &&
cp "$SRCDIR"/MANIFEST "$STAGE_DIR/src" || dienow

# Build busybox and toybox

build_section busybox
cp "$WORK"/config-busybox "$STAGE_DIR"/src || dienow
build_section toybox

# Put statically and dynamically linked hello world programs on there for
# test purposes.

"${ARCH}-cc" "${SOURCES}/toys/hello.c" -Os $CFLAGS -o "$STAGE_DIR/bin/hello-dynamic" || dienow

if [ ! -z "$BUILD_STATIC" ] && [ "$BUILD_STATIC" != none ]
then
  "${ARCH}-cc" "${SOURCES}/toys/hello.c" -Os $CFLAGS -static -o "$STAGE_DIR/bin/hello-static" || dienow
fi

# If a native compiler exists for this target, grab it

if [ -d "$BUILD/native-compiler-$ARCH" ]
then
  # Copy native compiler

  cp -a "$BUILD/native-compiler-$ARCH/." "$STAGE_DIR/" || dienow
else
  # Do we need shared libraries?

  if [ ! -z "$BUILD_STATIC" ] && [ "$BUILD_STATIC" != none ]
  then
    echo Copying compiler libraries...
    mkdir -p "$STAGE_DIR/lib" || dienow
    (path_search \
       "$("$ARCH-cc" --print-search-dirs | sed -n 's/^libraries: =*//p')" \
        "*.so*" 'cp -H "$DIR/$FILE" "$STAGE_DIR/lib/$FILE"' \
        || dienow) | dotprogress
  fi

  # Since we're not installing a compiler, delete the example source code.  
  rm -rf "$STAGE_DIR/src/*.c*" || dienow
fi

# This is allowed to fail if there are no configs.

mv "$STAGE_DIR/config-"* "$STAGE_DIR/src" 2>/dev/null

# Clean up and package the result

if [ -z "$SKIP_STRIP" ]
then
  "${ARCH}-strip" "$STAGE_DIR"/{bin/*,sbin/*,libexec/gcc/*/*/*}
  "${ARCH}-strip" --strip-unneeded "$STAGE_DIR"/lib/*.so
fi

create_stage_tarball

# Color back to normal
echo -e "\e[0mBuild complete"
