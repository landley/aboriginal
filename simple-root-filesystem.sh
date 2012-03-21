#!/bin/bash

# Build a basic busybox+uClibc root filesystem for a given target.

# Requires a cross-compiler (or simple-cross-compiler) in the $PATH or in
# the build directory.  In theory you can supply your own as long as the
# prefix- name is correct.

source sources/include.sh || exit 1
load_target "$1"
check_for_base_arch || exit 0
check_prerequisite "${ARCH}-cc"

# Determine which directory layout we're using

if [ -z "$ROOT_NODIRS" ]
then
  mkdir -p "$STAGE_DIR"/{tmp,proc,sys,dev,home,mnt,root} &&
  chmod a+rwxt "$STAGE_DIR/tmp" || dienow

  STAGE_USR="$STAGE_DIR/usr"

  # Having lots of repeated locations at / and also under /usr is silly, so
  # symlink them together.  (The duplication happened back in the 1970's
  # when Ken and Dennis ran out of space on their PDP-11's root disk and
  # leaked the OS into the disk containing the user home directories.  It's
  # been mindlessly duplicated ever since.)
  for i in bin sbin lib etc
  do
    mkdir -p "$STAGE_USR/$i" && ln -s "usr/$i" "$STAGE_DIR/$i" || dienow
  done

else
  STAGE_USR="$STAGE_DIR" && mkdir -p "$STAGE_DIR/bin" || dienow
fi

# Copy qemu setup script and so on.

cp -r "$SOURCES/root-filesystem/." "$STAGE_USR/" &&
echo -e "CROSS_TARGET=$CROSS_TARGET\nKARCH=$KARCH" > \
  "$STAGE_USR/src/host-info" &&
cp "$SRCDIR"/MANIFEST "$STAGE_USR/src" || dienow

# If user specified different files to put in the root filesystem, add them.
# (This overwrites existing files.)

if [ ! -z "$SIMPLE_ROOT_OVERLAY" ]
then
  cd "$TOP"
  tar -c -C "$SIMPLE_ROOT_OVERLAY" . | tar -x -C "$STAGE_DIR" || dienow
fi

# Build busybox

STAGE_DIR="$STAGE_USR" build_section busybox
cp "$WORK"/config-busybox "$STAGE_USR"/src || dienow

if [ "$TOYBOX" == toybox ]
then
  build_section toybox
fi

# Build the world's simplest init program: spawns one task with a controlling
# TTY, waits (reaping zombies) until it exits, then shuts down the system.

TEMP=
[ "$BUILD_STATIC" == all ] && TEMP=--static
${ARCH}-cc "$SOURCES/toys/oneit.c" -Os $CFLAGS $TEMP \
  -o "$STAGE_USR/sbin/oneit" || dienow

# Put statically and dynamically linked hello world programs on there for
# test purposes.

"${ARCH}-cc" "${SOURCES}/toys/hello.c" -Os $CFLAGS \
  -o "$STAGE_USR/bin/hello-dynamic" || dienow

if [ "$BUILD_STATIC" != none ]
then
  "${ARCH}-cc" "${SOURCES}/toys/hello.c" -Os $CFLAGS -static \
    -o "$STAGE_USR/bin/hello-static" || dienow
fi

# Debug wrapper for use with /usr/src/record-commands.sh

"${ARCH}-cc" "$SOURCES/toys/wrappy.c" -Os $CFLAGS -o "$STAGE_USR/bin/record-commands-wrapper" || dienow

# Do we need shared libraries?

if [ "$BUILD_STATIC" != all ]
then
  echo Copying compiler libraries...
  mkdir -p "$STAGE_USR/lib" || dienow
  (path_search \
     "$("$ARCH-cc" --print-search-dirs | sed -n 's/^libraries: =*//p')" \
      "*.so*" 'cp -H "$DIR/$FILE" "$STAGE_USR/lib/$FILE"' \
      || dienow) | dotprogress

  [ -z "$SKIP_STRIP" ] &&
    "${ARCH}-strip" --strip-unneeded "$STAGE_USR"/lib/*.so
fi

# Clean up and package the result

[ -z "$SKIP_STRIP" ] &&
  "${ARCH}-strip" "$STAGE_USR"/{bin/*,sbin/*}

create_stage_tarball

# Color back to normal
echo -e "\e[0mBuild complete"
