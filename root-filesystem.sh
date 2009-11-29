#!/bin/bash

# Build a root filesystem for a given target.

# Get lots of predefined environment variables and shell functions.

source sources/include.sh || exit 1

# Parse the sources/targets/$1 directory

read_arch_dir "$1"

# If this target has a base architecture that's already been built, use that.

check_for_base_arch || exit 0

# Announce start of stage.

echo "=== Building $STAGE_NAME"

# Die if our prerequisite isn't there.

for i in "$ARCH" "$FROM_ARCH"
do
  if [ -z "$(which "${i}-cc")" ]
  then
    [ -z "$FAIL_QUIET" ] && echo No "${i}-cc" in '$PATH'. >&2
    exit 1
  fi
done

# Determine which directory layout we're using

if [ -z "$ROOT_NODIRS" ]
then
  ROOT_TOPDIR="$STAGE_DIR/usr"
  mkdir -p "$STAGE_DIR"/{tmp,proc,sys,dev,home,mnt} &&
  chmod a+rwxt "$STAGE_DIR/tmp" || dienow
  for i in bin sbin lib etc
  do
    mkdir -p "$ROOT_TOPDIR/$i" || dienow
    ln -s "usr/$i" "$STAGE_DIR/$i" || dienow
  done
else
  ROOT_TOPDIR="$STAGE_DIR"
  mkdir -p "$STAGE_DIR/bin" || dienow
fi

# Build C Library

STAGE_DIR="$ROOT_TOPDIR" build_section linux-headers
STAGE_DIR="$ROOT_TOPDIR" build_section uClibc

if [ "$NATIVE_TOOLCHAIN" == "none" ]
then
    # If we're not installing a compiler, delete the headers, static libs,
	# and example source code.

    rm -rf "$ROOT_TOPDIR"/include &&
    rm -rf "$ROOT_TOPDIR"/lib/*.a &&
    rm -rf "$ROOT_TOPDIR/src" || dienow

elif [ "$NATIVE_TOOLCHAIN" == "headers" ]
then

# If you want to use a compiler other than gcc, you need to keep the headers,
# so do nothing here.
  echo

else

# Build binutils, gcc, and ccwrap

STAGE_DIR="$ROOT_TOPDIR" build_section binutils
STAGE_DIR="$ROOT_TOPDIR" build_section gcc
STAGE_DIR="$ROOT_TOPDIR" build_section ccwrap

# Tell future packages to link against the libraries in the new root filesystem,
# rather than the ones in the cross compiler directory.

export "$(echo $ARCH | sed 's/-/_/g')"_WRAPPER_TOPDIR="$ROOT_TOPDIR"

STAGE_DIR="$ROOT_TOPDIR" build_section uClibc++

fi # End of NATIVE_TOOLCHAIN build

if [ "$NATIVE_TOOLCHAIN" != "only" ]
then

# Copy qemu setup script and so on.

cp -r "${SOURCES}/native/." "$ROOT_TOPDIR/" &&
cp "$SRCDIR"/MANIFEST "$ROOT_TOPDIR/src" || dienow

STAGE_DIR="$ROOT_TOPDIR"/bin build_section busybox
cp "$WORK"/config-busybox "$ROOT_TOPDIR"/src || dienow

# Build and install make

setupfor make
LDFLAGS="$STATIC_FLAGS $LDFLAGS" CC="${ARCH}-cc" ./configure \
  --prefix="$ROOT_TOPDIR" --build="${CROSS_HOST}" --host="${CROSS_TARGET}" &&
make -j $CPUS &&
make -j $CPUS install

cleanup

# Build and install bash.  (Yes, this is an old version.  It's intentional.)

setupfor bash
# Remove existing /bin/sh link (busybox) so the bash install doesn't get upset.
#rm "$ROOT_TOPDIR"/bin/sh
# wire around some tests ./configure can't run when cross-compiling.
cat > config.cache << EOF &&
ac_cv_func_setvbuf_reversed=no
bash_cv_sys_named_pipes=yes
bash_cv_have_mbstate_t=yes
bash_cv_getenv_redef=no
EOF
LDFLAGS="$STATIC_FLAGS $LDFLAGS" CC="${ARCH}-cc" RANLIB="${ARCH}-ranlib" \
  ./configure --prefix="$ROOT_TOPDIR" \
  --build="${CROSS_HOST}" --host="${CROSS_TARGET}" --cache-file=config.cache \
  --without-bash-malloc --disable-readline &&
# note: doesn't work with -j
make &&
make install &&
# Make bash the default shell.
ln -sf bash "$ROOT_TOPDIR/bin/sh"

cleanup

setupfor distcc
rsync_cv_HAVE_C99_VSNPRINTF=yes \
LDFLAGS="$STATIC_FLAGS $LDFLAGS" CC="${ARCH}-cc" ./configure \
  --host="${CROSS_TARGET}" --prefix="$ROOT_TOPDIR" \
  --with-included-popt --disable-Werror &&
make -j $CPUS &&
make -j $CPUS install &&
mkdir -p "$ROOT_TOPDIR/distcc" || dienow

for i in gcc cc g++ c++
do
  ln -s ../bin/distcc "$ROOT_TOPDIR/distcc/$i" || dienow
done

cleanup

# Put statically and dynamically linked hello world programs on there for
# test purposes.

"${ARCH}-cc" "${SOURCES}/toys/hello.c" -Os -s -o "$ROOT_TOPDIR/bin/hello-dynamic" &&
"${ARCH}-cc" "${SOURCES}/toys/hello.c" -Os -s -static -o "$ROOT_TOPDIR/bin/hello-static"

[ $? -ne 0 ] && dienow

fi   # End of NATIVE_TOOLCHAIN != only

if [ -z "$SKIP_STRIP" ]
then
  # Delete some unneeded files

  rm -rf "$ROOT_TOPDIR"/{info,man,libexec/gcc/*/*/install-tools}

  # Clean up and package the result

  "${ARCH}-strip" "$ROOT_TOPDIR"/{bin/*,sbin/*,libexec/gcc/*/*/*}
  "${ARCH}-strip" --strip-unneeded "$ROOT_TOPDIR"/lib/*.so
fi

create_stage_tarball

# Color back to normal
echo -e "\e[0mBuild complete"
