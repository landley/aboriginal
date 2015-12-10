#!/bin/bash

# Build a basic busybox+uClibc root filesystem for a given target.

# Requires a cross-compiler (or simple-cross-compiler) in the $PATH or in
# the build directory.  In theory you can supply your own as long as the
# prefix- name is correct.

source sources/include.sh || exit 1
load_target "$1"
check_for_base_arch || exit 0
check_prerequisite "${CC_PREFIX}cc"

# Source control isn't good at storing empty directories, so create
# directory layout and apply permissions changes.

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

# Copy qemu setup script and so on.

cp -r "$SOURCES/root-filesystem/." "$STAGE_USR/" &&
echo -e "CROSS_TARGET=$CROSS_TARGET\nKARCH=$KARCH" > \
  "$STAGE_USR/src/host-info" &&
cp "$SRCDIR"/MANIFEST "$STAGE_USR/src" || dienow

# If user specified different files to put in the root filesystem, add them.
# (This overwrites existing files.)

if [ ! -z "$MY_ROOT_OVERLAY" ]
then
  cd "$TOP"
  tar -c -C "$MY_ROOT_OVERLAY" . | tar -x -C "$STAGE_DIR" || dienow
fi

# Build toybox

STAGE_DIR="$STAGE_USR" build_section busybox
cp "$WORK"/config-busybox "$STAGE_USR"/src || dienow
build_section toybox

# Put statically and dynamically linked hello world programs on there for
# test purposes.

"${CC_PREFIX}cc" "${SOURCES}/root-filesystem/src/hello.c" -Os $CFLAGS \
  -o "$STAGE_USR/bin/hello-dynamic" || dienow

if [ "$BUILD_STATIC" != none ]
then
  "${CC_PREFIX}cc" "${SOURCES}/root-filesystem/src/hello.c" -Os $CFLAGS -static \
    -o "$STAGE_USR/bin/hello-static" || dienow
  STATIC=--static
else
  STATIC=
fi

# Debug wrapper for use with /usr/src/record-commands.sh

"${CC_PREFIX}cc" "$SOURCES/toys/wrappy.c" -Os $CFLAGS $STATIC \
  -o "$STAGE_USR/bin/record-commands-wrapper" || dienow

# Do we need shared libraries?

if ! is_in_list toybox $BUILD_STATIC || ! is_in_list busybox $BUILD_STATIC
then
  echo Copying compiler libraries...
  mkdir -p "$STAGE_USR/lib" || dienow
  (path_search \
     "$("${CC_PREFIX}cc" --print-search-dirs | sed -n 's/^libraries: =*//p')" \
      "*.so*" 'cp -H "$DIR/$FILE" "$STAGE_USR/lib/$FILE"' \
      || dienow) | dotprogress

  [ -z "$SKIP_STRIP" ] &&
    "${CC_PREFIX}strip" --strip-unneeded "$STAGE_USR"/lib/*.so
fi

# Clean up and package the result

[ -z "$SKIP_STRIP" ] &&
  "${CC_PREFIX}strip" "$STAGE_USR"/{bin/*,sbin/*}

create_stage_tarball

# Color back to normal
echo -e "\e[0mBuild complete"
