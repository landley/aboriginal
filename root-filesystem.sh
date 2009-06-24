#!/bin/bash

# Get lots of predefined environment variables and shell functions.

source sources/include.sh || exit 1

# Parse the sources/targets/$1 directory

read_arch_dir "$1"

# If this target has a base architecture that's already been built, use that.

check_for_base_arch root-filesystem || exit 0

# Die if our prerequisite isn't there.

if [ -z "$(which "$ARCH-cc")" ]
then
  [ -z "$FAIL_QUIET" ] && echo No "$ARCH-cc" in '$PATH'. >&2
  exit 1
fi

# Announce start of stage.

echo -e "$NATIVE_COLOR"
echo "=== Building minimal native development environment"

blank_tempdir "$WORK"
blank_tempdir "$NATIVE_ROOT"

# Determine which directory layout we're using

if [ ! -z "${NATIVE_TOOLSDIR}" ]
then
  mkdir -p "${TOOLS}/bin" || dienow

  # Tell the wrapper script where to find the dynamic linker.
  export UCLIBC_DYNAMIC_LINKER=/tools/lib/ld-uClibc.so.0
  UCLIBC_TOPDIR="${NATIVE_ROOT}"
  UCLIBC_DLPREFIX="/tools"
else
  mkdir -p "${NATIVE_ROOT}"/{tmp,proc,sys,dev,home} || dienow
  UCLIBC_TOPDIR="${TOOLS}"
  for i in bin sbin lib etc
  do
    mkdir -p "$TOOLS/$i" || dienow
    ln -s "usr/$i" "${NATIVE_ROOT}/$i" || dienow
  done
fi

# Install Linux kernel headers.

setupfor linux
# Install Linux kernel headers (for use by uClibc).
make headers_install -j "$CPUS" ARCH="${KARCH}" INSTALL_HDR_PATH="${TOOLS}" &&
# This makes some very old package builds happy.
ln -s ../sys/user.h "${TOOLS}/include/asm/page.h" &&
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
  make CROSS="${ARCH}-" KERNEL_HEADERS="${TOOLS}/include" \
       PREFIX="${UCLIBC_TOPDIR}/" $VERBOSITY \
       RUNTIME_PREFIX="$UCLIBC_DLPREFIX/" DEVEL_PREFIX="$UCLIBC_DLPREFIX/" \
       UCLIBC_LDSO_NAME=ld-uClibc -j $CPUS $i || dienow
done

# There's no way to specify a prefix for the uClibc utils; rename them by hand.

if [ ! -z "$PROGRAM_PREFIX" ]
then
  for i in ldd readelf
  do
    mv "${TOOLS}"/bin/{"$i","${PROGRAM_PREFIX}$i"} || dienow
  done
fi

cd ..

cleanup uClibc

if [ "$NATIVE_TOOLCHAIN" == "none" ]
then
    # If we're not installing a compiler, delete the headers, static libs,
	# and example source code.

    rm -rf "${TOOLS}"/include &&
    rm -rf "${TOOLS}"/lib/*.a &&
    rm -rf "${TOOLS}/src" || dienow

elif [ "$NATIVE_TOOLCHAIN" == "headers" ]
then

# If you want to use a compiler other than gcc, you need to keep the headers,
# so do nothing here.
  echo

else

# Build and install native binutils

setupfor binutils build-binutils
CC="${FROM_ARCH}-cc" AR="${FROM_ARCH}-ar" "${CURSRC}/configure" --prefix="${TOOLS}" \
  --build="${CROSS_HOST}" --host="${FROM_HOST}" --target="${CROSS_TARGET}" \
  --disable-nls --disable-shared --disable-multilib --disable-werror \
  --program-prefix="$PROGRAM_PREFIX" $BINUTILS_FLAGS &&
make -j $CPUS configure-host &&
make -j $CPUS CFLAGS="-O2 $STATIC_FLAGS" &&
make -j $CPUS install &&
cd .. &&
mkdir -p "${TOOLS}/include" &&
cp binutils/include/libiberty.h "${TOOLS}/include"

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
  "${CURSRC}/configure" --prefix="${TOOLS}" --disable-multilib \
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
ln -s lib "$TOOLS/lib64" &&
make -j $CPUS install-gcc &&
rm "$TOOLS/lib64" &&
ln -s "${PROGRAM_PREFIX}gcc" "${TOOLS}/bin/${PROGRAM_PREFIX}cc" &&
# Now we need to beat libsupc++ out of gcc (which uClibc++ needs to build).
# But don't want to build the whole of libstdc++-v3 because
# A) we're using uClibc++ instead,  B) the build breaks.
make -j $CPUS configure-target-libstdc++-v3 &&
cd "$CROSS_TARGET"/libstdc++-v3/libsupc++ &&
make -j $CPUS &&
mv .libs/libsupc++.a "$TOOLS"/lib &&
cd ../../../..

cleanup gcc-core build-gcc

# Move the gcc internal libraries and headers somewhere sane

mkdir -p "${TOOLS}"/gcc &&
mv "${TOOLS}"/lib/gcc/*/*/include "${TOOLS}"/gcc/include &&
mv "${TOOLS}"/lib/gcc/*/* "${TOOLS}"/gcc/lib &&

# Rub gcc's nose in the binutils output.
cd "${TOOLS}"/libexec/gcc/*/*/ &&
cp -s "../../../../$CROSS_TARGET/bin/"* . &&

# build and install gcc wrapper script.
mv "${TOOLS}/bin/${PROGRAM_PREFIX}gcc" "${TOOLS}/bin/${PROGRAM_PREFIX}rawgcc" &&
"${FROM_ARCH}-gcc" "${SOURCES}"/toys/ccwrap.c -Os -s \
  -o "${TOOLS}/bin/${PROGRAM_PREFIX}gcc" -DGIMME_AN_S $STATIC_FLAGS \
  -DGCC_UNWRAPPED_NAME='"'"${PROGRAM_PREFIX}rawgcc"'"' &&

# Wrap C++
mv "${TOOLS}/bin/${PROGRAM_PREFIX}g++" "${TOOLS}/bin/${PROGRAM_PREFIX}rawg++" &&
ln "${TOOLS}/bin/${PROGRAM_PREFIX}gcc" "${TOOLS}/bin/${PROGRAM_PREFIX}g++" &&
rm "${TOOLS}/bin/${PROGRAM_PREFIX}c++" &&
ln -s "${PROGRAM_PREFIX}g++" "${TOOLS}/bin/${PROGRAM_PREFIX}c++"

cleanup "${TOOLS}"/{lib/gcc,gcc/lib/install-tools,bin/${ARCH}-unknown-*}

# Tell future packages to link against the libraries in root-filesystem,
# rather than the ones in the cross compiler directory.

export WRAPPER_TOPDIR="${TOOLS}"

# Build and install uClibc++

setupfor uClibc++
CROSS= make defconfig &&
sed -r -i 's/(UCLIBCXX_HAS_(TLS|LONG_DOUBLE))=y/# \1 is not set/' .config &&
sed -r -i '/UCLIBCXX_RUNTIME_PREFIX=/s/".*"/""/' .config &&
CROSS= make oldconfig &&
CROSS="$ARCH"- make &&
CROSS= make install PREFIX="${TOOLS}/c++" &&

# Move libraries somewhere useful.

mv "${TOOLS}"/c++/lib/* "${TOOLS}"/lib &&
rm -rf "${TOOLS}"/c++/{lib,bin} &&
ln -s libuClibc++.so "${TOOLS}"/lib/libstdc++.so &&
ln -s libuClibc++.a "${TOOLS}"/lib/libstdc++.a &&
cd ..

cleanup uClibc++

fi # End of NATIVE_TOOLCHAIN build

if [ "$NATIVE_TOOLCHAIN" != "only" ]
then

# Copy qemu setup script and so on.

cp -r "${SOURCES}/native/." "${TOOLS}/" &&
cp "$SRCDIR"/MANIFEST "${TOOLS}/src" &&
cp "${WORK}/config-uClibc" "${TOOLS}/src/config-uClibc" || dienow

if [ -z "${NATIVE_TOOLSDIR}" ]
then
  sed -i -e 's@/tools/@/usr/@g' "${TOOLS}/sbin/init.sh" || dienow
fi

# Build and install toybox

setupfor toybox
make defconfig &&
if [ -z "$USE_TOYBOX" ]
then
  CFLAGS="$CFLAGS $STATIC_FLAGS" make CROSS="${ARCH}-" &&
  cp toybox "$TOOLS/bin" &&
  ln -s toybox "$TOOLS/bin/patch" &&
  ln -s toybox "$TOOLS/bin/oneit" &&
  ln -s toybox "$TOOLS/bin/netcat" &&
  cd ..
else
  CFLAGS="$CFLAGS $STATIC_FLAGS" \
    make install_flat PREFIX="${TOOLS}"/bin CROSS="${ARCH}-" &&
  cd ..
fi

cleanup toybox

# Build and install busybox

setupfor busybox
make allyesconfig KCONFIG_ALLCONFIG="${SOURCES}/trimconfig-busybox" &&
cp .config "${TOOLS}"/src/config-busybox &&
LDFLAGS="$LDFLAGS $STATIC_FLAGS" \
  make -j $CPUS CROSS_COMPILE="${ARCH}-" $VERBOSITY &&
make busybox.links &&
cp busybox "${TOOLS}/bin"

[ $? -ne 0 ] && dienow

for i in $(sed 's@.*/@@' busybox.links)
do
  # Allowed to fail.
  ln -s busybox "${TOOLS}/bin/$i" 2>/dev/null
done
cd ..

cleanup busybox

# Build and install make

setupfor make
CC="${ARCH}-gcc" ./configure --prefix="${TOOLS}" --build="${CROSS_HOST}" \
  --host="${CROSS_TARGET}" &&
make -j $CPUS &&
make -j $CPUS install &&
cd ..

cleanup make

# Build and install bash.  (Yes, this is an old version.  It's intentional.)

setupfor bash
# Remove existing /bin/sh link (busybox) so the bash install doesn't get upset.
#rm "$TOOLS"/bin/sh
# wire around some tests ./configure can't run when cross-compiling.
cat > config.cache << EOF &&
ac_cv_func_setvbuf_reversed=no
bash_cv_sys_named_pipes=yes
bash_cv_have_mbstate_t=yes
bash_cv_getenv_redef=no
EOF
CC="${ARCH}-gcc" RANLIB="${ARCH}-ranlib" ./configure --prefix="${TOOLS}" \
  --build="${CROSS_HOST}" --host="${CROSS_TARGET}" --cache-file=config.cache \
  --without-bash-malloc --disable-readline &&
# note: doesn't work with -j
make &&
make install &&
# Make bash the default shell.
ln -sf bash "${TOOLS}/bin/sh" &&
cd ..

cleanup bash

setupfor distcc
CC="${ARCH}-cc" ./configure --host="${CROSS_TARGET}" --prefix="${TOOLS}" \
  --with-included-popt --disable-Werror &&
make -j $CPUS &&
make -j $CPUS install &&
mkdir -p "${TOOLS}/distcc" || dienow

for i in gcc cc g++ c++
do
  ln -s ../bin/distcc "${TOOLS}/distcc/$i" || dienow
done
cd ..

cleanup distcc

# Put statically and dynamically linked hello world programs on there for
# test purposes.

"${ARCH}-gcc" "${SOURCES}/toys/hello.c" -Os -s -o "${TOOLS}/bin/hello-dynamic" &&
"${ARCH}-gcc" "${SOURCES}/toys/hello.c" -Os -s -static -o "${TOOLS}/bin/hello-static"

[ $? -ne 0 ] && dienow

fi   # End of NATIVE_TOOLCHAIN != only

# Delete some unneeded files

rm -rf "${TOOLS}"/{info,man,libexec/gcc/*/*/install-tools}

# Clean up and package the result

"${ARCH}-strip" "${TOOLS}"/{bin/*,sbin/*,libexec/gcc/*/*/*}
"${ARCH}-strip" --strip-unneeded "${TOOLS}"/lib/*.so

create_stage_tarball root-filesystem

# Color back to normal
echo -e "\e[0mBuild complete"
