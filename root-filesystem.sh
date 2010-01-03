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

cp -r "${SOURCES}/native/." "$STAGE_DIR/" &&
cp "$SRCDIR"/MANIFEST "$STAGE_DIR/src" || dienow

# Build busybox and toybox

STAGE_DIR="$STAGE_DIR"/bin build_section busybox
cp "$WORK"/config-busybox "$STAGE_DIR"/src || dienow

STAGE_DIR="$STAGE_DIR"/bin build_section toybox

# Put statically and dynamically linked hello world programs on there for
# test purposes.

"${ARCH}-cc" "${SOURCES}/toys/hello.c" -Os $CFLAGS -o "$STAGE_DIR/bin/hello-dynamic" &&
"${ARCH}-cc" "${SOURCES}/toys/hello.c" -Os $CFLAGS -static -o "$STAGE_DIR/bin/hello-static" || dienow

# If no native compiler exists for this target...

if [ ! -d "$BUILD/native-compiler-$ARCH" ]
then

  # Do we need shared libraries?

  if [ ! -z "$BUILD_STATIC" ]
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

# If a native compiler exists for this target, use it and add supplementary
# development tools

else

  # Copy native compiler

  cp -a "$BUILD/native-compiler-$ARCH/." "$STAGE_DIR/" || dienow

  # Build and install make

  setupfor make
  LDFLAGS="$STATIC_FLAGS $LDFLAGS" CC="${ARCH}-cc" ./configure \
    --prefix="$STAGE_DIR" --build="${CROSS_HOST}" --host="${CROSS_TARGET}" &&
  make -j $CPUS &&
  make -j $CPUS install

  cleanup

  # Build and install bash.  (Yes, this is an old version.  It's intentional.)

  setupfor bash
  # wire around some tests ./configure can't run when cross-compiling.
  echo -e "ac_cv_func_setvbuf_reversed=no\nbash_cv_sys_named_pipes=yes\nbash_cv_have_mbstate_t=yes\nbash_cv_getenv_redef=no" > config.cache &&
  LDFLAGS="$STATIC_FLAGS $LDFLAGS" CC="${ARCH}-cc" RANLIB="${ARCH}-ranlib" \
    ./configure --prefix="$STAGE_DIR" \
    --build="${CROSS_HOST}" --host="${CROSS_TARGET}" --cache-file=config.cache \
    --without-bash-malloc --disable-readline &&
  # note: doesn't work with -j
  make &&
  make install &&
  # Make bash the default shell.
  ln -sf bash "$STAGE_DIR/bin/sh"

  cleanup

  # Build and install distcc

  setupfor distcc
  rsync_cv_HAVE_C99_VSNPRINTF=yes \
  LDFLAGS="$STATIC_FLAGS $LDFLAGS" CC="${ARCH}-cc" ./configure \
    --host="${CROSS_TARGET}" --prefix="$STAGE_DIR" \
    --with-included-popt --disable-Werror &&
  make -j $CPUS &&
  make -j $CPUS install &&
  mkdir -p "$STAGE_DIR/distcc" || dienow

  for i in gcc cc g++ c++
  do
    ln -s ../bin/distcc "$STAGE_DIR/distcc/$i" || dienow
  done

  cleanup

  # Delete some unneeded files

  [ -z "$SKIP_STRIP" ] &&
    rm -rf "$STAGE_DIR"/{info,man,libexec/gcc/*/*/install-tools}

fi # native compiler

# Clean up and package the result

if [ -z "$SKIP_STRIP" ]
then
  "${ARCH}-strip" "$STAGE_DIR"/{bin/*,sbin/*,libexec/gcc/*/*/*}
  "${ARCH}-strip" --strip-unneeded "$STAGE_DIR"/lib/*.so
fi

create_stage_tarball

# Color back to normal
echo -e "\e[0mBuild complete"
