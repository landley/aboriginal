#!/bin/bash

# Get lots of predefined environment variables and shell functions.

source sources/include.sh || exit 1

# Parse the sources/targets/$1 directory

read_arch_dir "$1"

# If this target has a base architecture that's already been built, use that.

check_for_base_arch || exit 0

# Die if our prerequisite isn't there.

for i in "$ARCH" "$FROM_ARCH"
do
  if [ -z "$(which "${i}-cc")" ]
  then
    [ -z "$FAIL_QUIET" ] && echo No "${i}-cc" in '$PATH'. >&2
    exit 1
  fi
done

# Announce start of stage.

echo -e "$NATIVE_COLOR"
echo "=== Building $STAGE_NAME"

blank_tempdir "$WORK"
blank_tempdir "$STAGE_DIR"

# Determine which directory layout we're using

if [ -z "$ROOT_NODIRS" ]
then
  ROOT_TOPDIR="$STAGE_DIR/usr"
  mkdir -p "$STAGE_DIR"/{tmp,proc,sys,dev,home} || dienow
  for i in bin sbin lib etc
  do
    mkdir -p "$ROOT_TOPDIR/$i" || dienow
    ln -s "usr/$i" "$STAGE_DIR/$i" || dienow
  done
else
  ROOT_TOPDIR="$STAGE_DIR"
  mkdir -p "$STAGE_DIR/bin" || dienow
fi

# Install Linux kernel headers.

setupfor linux
# Install Linux kernel headers (for use by uClibc).
make headers_install -j "$CPUS" ARCH="${KARCH}" INSTALL_HDR_PATH="$ROOT_TOPDIR" &&
# This makes some very old package builds happy.
ln -s ../sys/user.h "$ROOT_TOPDIR/include/asm/page.h" &&
cd ..

cleanup linux

# Build and install uClibc.  (We could just copy the one from the compiler
# toolchain, but this is cleaner.)

setupfor uClibc
make CROSS="${ARCH}-" KCONFIG_ALLCONFIG="$(getconfig uClibc)" allnoconfig &&
cp .config "${WORK}"/config-uClibc || dienow

# Alas, if we feed install and install_utils to make at the same time with
# -j > 1, it dies.  Not SMP safe.
for i in install install_utils
do
  make CROSS="${ARCH}-" KERNEL_HEADERS="$ROOT_TOPDIR/include" \
       PREFIX="$ROOT_TOPDIR/" $VERBOSITY \
       RUNTIME_PREFIX="/" DEVEL_PREFIX="/" \
       UCLIBC_LDSO_NAME=ld-uClibc -j $CPUS $i || dienow
done

# There's no way to specify a prefix for the uClibc utils; rename them by hand.

if [ ! -z "$PROGRAM_PREFIX" ]
then
  for i in ldd readelf
  do
    mv "$ROOT_TOPDIR"/bin/{"$i","${PROGRAM_PREFIX}$i"} || dienow
  done
fi

cd ..

cleanup uClibc

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

# Build and install native binutils

setupfor binutils build-binutils
CC="${FROM_ARCH}-cc" AR="${FROM_ARCH}-ar" "${CURSRC}/configure" --prefix="$ROOT_TOPDIR" \
  --build="${CROSS_HOST}" --host="${FROM_HOST}" --target="${CROSS_TARGET}" \
  --disable-nls --disable-shared --disable-multilib --disable-werror \
  --program-prefix="$PROGRAM_PREFIX" $BINUTILS_FLAGS &&
make -j $CPUS configure-host &&
make -j $CPUS CFLAGS="-O2 $STATIC_FLAGS" &&
make -j $CPUS install &&
cd .. &&
mkdir -p "$ROOT_TOPDIR/include" &&
cp binutils/include/libiberty.h "$ROOT_TOPDIR/include"

cleanup binutils build-binutils

# Build and install native gcc, with c++ support this time.

setupfor gcc-core build-gcc
setupfor gcc-g++ build-gcc gcc-core
# GCC tries to "help out in the kitchen" by screwing up the linux include
# files.  Cut out those bits with sed and throw them away.
sed -i 's@^STMP_FIX.*@@' "${CURSRC}/gcc/Makefile.in" &&
# GCC has some deep assumptions about the name of the cross-compiler it should
# be using.  These assumptions are wrong, and lots of redundant corrections
# are required to make it stop.
CC="${FROM_ARCH}-cc" AR="${FROM_ARCH}-ar" AS="${FROM_ARCH}-as" \
  LD="${FROM_ARCH}-ld" NM="${FROM_ARCH}-nm" \
  CC_FOR_TARGET="${ARCH}-cc" AR_FOR_TARGET="${ARCH}-ar" \
  NM_FOR_TARGET="${ARCH}-nm" GCC_FOR_TARGET="${ARCH}-cc" \
  AS_FOR_TARGET="${ARCH}-as" LD_FOR_TARGET="${ARCH}-ld" \
  CXX_FOR_TARGET="${ARCH}-g++" \
  ac_cv_path_AR_FOR_TARGET="${ARCH}-ar" \
  ac_cv_path_RANLIB_FOR_TARGET="${ARCH}-ranlib" \
  ac_cv_path_NM_FOR_TARGET="${ARCH}-nm" \
  ac_cv_path_AS_FOR_TARGET="${ARCH}-as" \
  ac_cv_path_LD_FOR_TARGET="${ARCH}-ld" \
  "${CURSRC}/configure" --prefix="$ROOT_TOPDIR" --disable-multilib \
  --build="${CROSS_HOST}" --host="${CROSS_TARGET}" --target="${CROSS_TARGET}" \
  --enable-long-long --enable-c99 --enable-shared --enable-threads=posix \
  --enable-__cxa_atexit --disable-nls --enable-languages=c,c++ \
  --disable-libstdcxx-pch --program-prefix="$PROGRAM_PREFIX" \
  $GCC_FLAGS &&
mkdir gcc &&
ln -s `which "${ARCH}-gcc"` gcc/xgcc &&
make -j $CPUS configure-host &&
make -j $CPUS all-gcc LDFLAGS="$STATIC_FLAGS" &&
# Work around gcc bug; we disabled multilib but it doesn't always notice.
ln -s lib "$ROOT_TOPDIR/lib64" &&
make -j $CPUS install-gcc &&
rm "$ROOT_TOPDIR/lib64" &&
ln -s "${PROGRAM_PREFIX}gcc" "$ROOT_TOPDIR/bin/${PROGRAM_PREFIX}cc" &&
# Now we need to beat libsupc++ out of gcc (which uClibc++ needs to build).
# But don't want to build the whole of libstdc++-v3 because
# A) we're using uClibc++ instead,  B) the build breaks.
make -j $CPUS configure-target-libstdc++-v3 &&
cd "$CROSS_TARGET"/libstdc++-v3/libsupc++ &&
make -j $CPUS &&
mv .libs/libsupc++.a "$ROOT_TOPDIR"/lib &&
cd ../../../..

cleanup gcc-core build-gcc

# Move the gcc internal libraries and headers somewhere sane

mkdir -p "$ROOT_TOPDIR"/gcc &&
mv "$ROOT_TOPDIR"/lib/gcc/*/*/include "$ROOT_TOPDIR"/gcc/include &&
mv "$ROOT_TOPDIR"/lib/gcc/*/* "$ROOT_TOPDIR"/gcc/lib &&

# Rub gcc's nose in the binutils output.
cd "$ROOT_TOPDIR"/libexec/gcc/*/*/ &&
cp -s "../../../../$CROSS_TARGET/bin/"* . &&

# build and install gcc wrapper script.
mv "$ROOT_TOPDIR/bin/${PROGRAM_PREFIX}gcc" "$ROOT_TOPDIR/bin/${PROGRAM_PREFIX}rawgcc" &&
"${FROM_ARCH}-cc" "${SOURCES}"/toys/ccwrap.c -Os -s \
  -o "$ROOT_TOPDIR/bin/${PROGRAM_PREFIX}gcc" -DGIMME_AN_S $STATIC_FLAGS \
  -DGCC_UNWRAPPED_NAME='"'"${PROGRAM_PREFIX}rawgcc"'"' &&

# Wrap C++
mv "$ROOT_TOPDIR/bin/${PROGRAM_PREFIX}g++" "$ROOT_TOPDIR/bin/${PROGRAM_PREFIX}rawg++" &&
ln "$ROOT_TOPDIR/bin/${PROGRAM_PREFIX}gcc" "$ROOT_TOPDIR/bin/${PROGRAM_PREFIX}g++" &&
rm "$ROOT_TOPDIR/bin/${PROGRAM_PREFIX}c++" &&
ln -s "${PROGRAM_PREFIX}g++" "$ROOT_TOPDIR/bin/${PROGRAM_PREFIX}c++"

cleanup "$ROOT_TOPDIR"/{lib/gcc,gcc/lib/install-tools,bin/${ARCH}-unknown-*}

# Tell future packages to link against the libraries in the new root filesystem,
# rather than the ones in the cross compiler directory.

export WRAPPER_TOPDIR="$ROOT_TOPDIR"

# Build and install uClibc++

setupfor uClibc++
CROSS= make defconfig &&
sed -r -i 's/(UCLIBCXX_HAS_(TLS|LONG_DOUBLE))=y/# \1 is not set/' .config &&
sed -r -i '/UCLIBCXX_RUNTIME_PREFIX=/s/".*"/""/' .config &&
CROSS= make oldconfig &&
CROSS="$ARCH"- make &&
CROSS= make install PREFIX="$ROOT_TOPDIR/c++" &&

# Move libraries somewhere useful.

mv "$ROOT_TOPDIR"/c++/lib/* "$ROOT_TOPDIR"/lib &&
rm -rf "$ROOT_TOPDIR"/c++/{lib,bin} &&
ln -s libuClibc++.so "$ROOT_TOPDIR"/lib/libstdc++.so &&
ln -s libuClibc++.a "$ROOT_TOPDIR"/lib/libstdc++.a &&
cd ..

cleanup uClibc++

fi # End of NATIVE_TOOLCHAIN build

if [ "$NATIVE_TOOLCHAIN" != "only" ]
then

# Copy qemu setup script and so on.

cp -r "${SOURCES}/native/." "$ROOT_TOPDIR/" &&
cp "$SRCDIR"/MANIFEST "$ROOT_TOPDIR/src" &&
cp "${WORK}/config-uClibc" "$ROOT_TOPDIR/src/config-uClibc" || dienow

# Build and install toybox

setupfor toybox
make defconfig &&
if [ -z "$USE_TOYBOX" ]
then
  CFLAGS="$CFLAGS $STATIC_FLAGS" make CROSS="${ARCH}-" &&
  cp toybox "$ROOT_TOPDIR/bin" &&
  ln -s toybox "$ROOT_TOPDIR/bin/patch" &&
  ln -s toybox "$ROOT_TOPDIR/bin/oneit" &&
  ln -s toybox "$ROOT_TOPDIR/bin/netcat" &&
  cd ..
else
  CFLAGS="$CFLAGS $STATIC_FLAGS" \
    make install_flat PREFIX="$ROOT_TOPDIR"/bin CROSS="${ARCH}-" &&
  cd ..
fi

cleanup toybox

# Build and install busybox

setupfor busybox
make allyesconfig KCONFIG_ALLCONFIG="${SOURCES}/trimconfig-busybox" &&
cp .config "$ROOT_TOPDIR"/src/config-busybox &&
LDFLAGS="$LDFLAGS $STATIC_FLAGS" \
  make -j $CPUS CROSS_COMPILE="${ARCH}-" $VERBOSITY &&
make busybox.links &&
cp busybox "$ROOT_TOPDIR/bin"

[ $? -ne 0 ] && dienow

for i in $(sed 's@.*/@@' busybox.links)
do
  # Allowed to fail.
  ln -s busybox "$ROOT_TOPDIR/bin/$i" 2>/dev/null
done
cd ..

cleanup busybox

# Build and install make

setupfor make
LDFLAGS="$STATIC_FLAGS $LDFLAGS" CC="${ARCH}-cc" ./configure \
  --prefix="$ROOT_TOPDIR" --build="${CROSS_HOST}" --host="${CROSS_TARGET}" &&
make -j $CPUS &&
make -j $CPUS install &&
cd ..

cleanup make

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
ln -sf bash "$ROOT_TOPDIR/bin/sh" &&
cd ..

cleanup bash

setupfor distcc
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
cd ..

cleanup distcc

# Put statically and dynamically linked hello world programs on there for
# test purposes.

"${ARCH}-cc" "${SOURCES}/toys/hello.c" -Os -s -o "$ROOT_TOPDIR/bin/hello-dynamic" &&
"${ARCH}-cc" "${SOURCES}/toys/hello.c" -Os -s -static -o "$ROOT_TOPDIR/bin/hello-static"

[ $? -ne 0 ] && dienow

fi   # End of NATIVE_TOOLCHAIN != only

# Delete some unneeded files

rm -rf "$ROOT_TOPDIR"/{info,man,libexec/gcc/*/*/install-tools}

# Clean up and package the result

"${ARCH}-strip" "$ROOT_TOPDIR"/{bin/*,sbin/*,libexec/gcc/*/*/*}
"${ARCH}-strip" --strip-unneeded "$ROOT_TOPDIR"/lib/*.so

create_stage_tarball

# Color back to normal
echo -e "\e[0mBuild complete"
