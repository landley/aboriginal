#!/bin/bash

# Build a basic busybox+uClibc root filesystem for a given target.

# Requires a cross-compiler (or simple-cross-compiler) in the $PATH or in
# the build directory.  In theory you can supply your own as long as the
# prefix- name is correct.

source sources/include.sh || exit 1
read_arch_dir "$1"
check_for_base_arch || exit 0
check_prerequisite "${ARCH}-cc"

# Announce start of stage.

echo "=== Building $STAGE_NAME"

# Determine which directory layout we're using

OLD_STAGE_DIR="$STAGE_DIR"
if [ -z "$ROOT_NODIRS" ]
then
  mkdir -p "$STAGE_DIR"/{tmp,proc,sys,dev,home,mnt} &&
  chmod a+rwxt "$STAGE_DIR/tmp" || dienow

  # Having lots of repeated locations at / and also under /usr is silly, so
  # symlink them together.  (The duplication happened back in the 1970's
  # when Ken and Dennis ran out of space on their first RK05 disk pack and
  # leaked the OS into the disk containing the user home directories.  It's
  # been mindlessly duplicated ever since.)
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

cp -r "$SOURCES/root-filesystem/." "$STAGE_DIR/" &&
echo -e "CROSS_TARGET=$CROSS_TARGET\nKARCH=$KARCH" > \
  "$STAGE_DIR/src/host-info" &&
cp "$SRCDIR"/MANIFEST "$STAGE_DIR/src" || dienow

# If user specified different files to put in the root filesystem, add them.
# (This overwrites existing files.)

if [ ! -z "$SIMPLE_ROOT_OVERLAY" ]
then
  cd "$TOP"
  tar -cz -C "$SIMPLE_ROOT_OVERLAY" | tar -xz -C "$OLD_STAGE_DIR" || dienow
fi

# Build busybox

build_section busybox
cp "$WORK"/config-busybox "$STAGE_DIR"/src || dienow

# Build the world's simplest init program: spawns one task with a controlling
# TTY, waits (reaping zombies) until it exits, then shuts down the system.

TEMP=
[ "$BUILD_STATIC" == all ] && TEMP=--static
${ARCH}-cc "$SOURCES/toys/oneit.c" -Os $CFLAGS $TEMP \
  -o "$STAGE_DIR/sbin/oneit" || dienow

# Put statically and dynamically linked hello world programs on there for
# test purposes.

"${ARCH}-cc" "${SOURCES}/toys/hello.c" -Os $CFLAGS -o "$STAGE_DIR/bin/hello-dynamic" || dienow

if [ "$BUILD_STATIC" != none ]
then
  "${ARCH}-cc" "${SOURCES}/toys/hello.c" -Os $CFLAGS -static -o "$STAGE_DIR/bin/hello-static" || dienow
fi

# Do we need shared libraries?

if [ "$BUILD_STATIC" != all ]
then
  echo Copying compiler libraries...
  mkdir -p "$STAGE_DIR/lib" || dienow
  (path_search \
     "$("$ARCH-cc" --print-search-dirs | sed -n 's/^libraries: =*//p')" \
      "*.so*" 'cp -H "$DIR/$FILE" "$STAGE_DIR/lib/$FILE"' \
      || dienow) | dotprogress

  [ -z "$SKIP_STRIP" ] &&
    "${ARCH}-strip" --strip-unneeded "$STAGE_DIR"/lib/*.so
fi

# Clean up and package the result

[ -z "$SKIP_STRIP" ] &&
  "${ARCH}-strip" "$STAGE_DIR"/{bin/*,sbin/*}

create_stage_tarball

# Color back to normal
echo -e "\e[0mBuild complete"
