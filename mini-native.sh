#!/bin/bash

# Get lots of predefined environment variables and shell functions.

source include.sh

# Purple.  And why not?
echo -e "$NATIVE_COLOR"
echo "=== Building minimal native development environment"

rm -rf "${NATIVE}"

if [ -z "${NATIVE_NOTOOLSDIR}" ]
then
  TOOLS="${NATIVE}/tools"
  mkdir -p "${TOOLS}/bin" || dienow

  # Tell the wrapper script where to find the dynamic linker.
  export UCLIBC_DYNAMIC_LINKER=/tools/lib/ld-uClibc.so.0
  export UCLIBC_RPATH=/tools/lib
else
  mkdir -p "${NATIVE}"/{tmp,proc,sys,dev,etc} || dienow
  TOOLS="${NATIVE}/usr"
  for i in bin sbin lib
  do
    mkdir -p "$TOOLS/$i" || dienow
    ln -s "usr/$i" "${NATIVE}/$i" || dienow
  done
fi

# Copy qemu setup script and so on.

cp -r "${SOURCES}/native/." "${TOOLS}/" || dienow

# Build and install Linux kernel.

setupfor linux
# Install Linux kernel headers (for use by uClibc).
make headers_install -j "$CPUS" ARCH="${KARCH}" INSTALL_HDR_PATH="${TOOLS}" &&
# build bootable kernel for target
make ARCH="${KARCH}" KCONFIG_ALLCONFIG="${CONFIG_DIR}/miniconfig-linux" \
  allnoconfig &&
cp .config "${TOOLS}"/src/config-linux &&
make -j $CPUS ARCH="${KARCH}" CROSS_COMPILE="${ARCH}-" &&
cp "${KERNEL_PATH}" "${WORK}/zImage-${ARCH}" &&
cd ..

cleanup linux

# Build and install uClibc.  (We could just copy the one from the compiler
# toolchain, but this is cleaner.)

setupfor uClibc
if unstable uClibc
then
  CONFIGFILE=miniconfig-alt-uClibc
  BUILDIT="install -j $CPUS"
else
  CONFIGFILE=miniconfig-uClibc
  BUILDIT="install -j $CPUS"
fi
make CROSS="${ARCH}=" KCONFIG_ALLCONFIG="${CONFIG_DIR}"/$CONFIGFILE allnoconfig &&
cp .config "${TOOLS}"/src/config-uClibc &&
make CROSS="${ARCH}-" KERNEL_HEADERS="${TOOLS}/include" PREFIX="${TOOLS}/" \
     RUNTIME_PREFIX=/ DEVEL_PREFIX=/ UCLIBC_LDSO_NAME=ld-uClibc $BUILDIT &&
# utils_install wants to put stuff in usr/bin instead of bin.
# make BLAH=blah utils
# install -m 755 utils/{readelf,ldd,ldconfig} "${TOOLS}/bin" &&
cd ..

cleanup uClibc

# Build and install toybox

setupfor toybox
make defconfig &&
if [ -z "$USE_TOYBOX" ]
then
  make CROSS="${ARCH}-" &&
  cp toybox "$TOOLS/bin" &&
  ln -s toybox "$TOOLS/bin/patch" &&
  ln -s toybox "$TOOLS/bin/oneit" &&
  cd ..
else
  make install_flat PREFIX="${TOOLS}"/bin CROSS="${ARCH}-" &&
  rm "${TOOLS}"/bin/sh &&  # Bash won't install if this exists.
  cd ..
fi

cleanup toybox

# Build and install busybox

setupfor busybox
make allyesconfig KCONFIG_ALLCONFIG="${SOURCES}/trimconfig-busybox" &&
make -j $CPUS CROSS_COMPILE="${ARCH}-" &&
make busybox.links &&
cp busybox "${TOOLS}/bin"

[ $? -ne 0 ] && dienow

for i in $(sed 's@.*/@@' busybox.links)
do
  ln -s busybox "${TOOLS}/bin/$i" # || dienow
done
cd ..

cleanup busybox

if [ ! -z "${NATIVE_NOTOOLSDIR}" ]
then
  sed -i -e 's@/tools/@/usr/@g' "${TOOLS}/bin/qemu-setup.sh" || dienow
fi

# If you want to use tinycc, you need to keep the headers but don't need gcc.
if [ ! -z "$NATIVE_NOTOOLCHAIN" ]
then

  if [ "$NATIVE_NOTOOLCHAIN" != "headers" ]
  then
    rm -rf "${TOOLS}"/include &&
    rm -rf "${TOOLS}/src" || dienow
  fi

else

# Build and install native binutils

setupfor binutils build-binutils
CC="${ARCH}-gcc" AR="${ARCH}-ar" "${CURSRC}/configure" --prefix="${TOOLS}" \
  --build="${CROSS_HOST}" --host="${CROSS_TARGET}" --target="${CROSS_TARGET}" \
  --disable-nls --disable-shared --disable-multilib --program-prefix= \
  --disable-werror $BINUTILS_FLAGS &&
make -j $CPUS configure-host &&
make -j $CPUS &&
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
CC="${ARCH}-gcc" GCC_FOR_TARGET="${ARCH}-gcc" CC_FOR_TARGET="${ARCH}-gcc" \
  AR="${ARCH}-ar" AR_FOR_TARGET="${ARCH}-ar" AS="${ARCH}-as" LD="${ARCH}-ld" \
  NM="${ARCH}-nm" NM_FOR_TARGET="${ARCH}-nm" CXX_FOR_TARGET="${ARCH}-g++" \
  "${CURSRC}/configure" --prefix="${TOOLS}" --disable-multilib \
  --build="${CROSS_HOST}" --host="${CROSS_TARGET}" --target="${CROSS_TARGET}" \
  --enable-long-long --enable-c99 --enable-shared --enable-threads=posix \
  --enable-__cxa_atexit --disable-nls --enable-languages=c,c++ \
  --disable-libstdcxx-pch --enable-sjlj-exceptions --program-prefix="" \
  $GCC_FLAGS &&
make -j $CPUS configure-host &&
make -j $CPUS all-gcc &&
# Work around gcc bug; we disabled multilib but it doesn't always notice.
ln -s lib "$TOOLS/lib64" &&
make -j $CPUS install-gcc &&
rm "$TOOLS/lib64" &&
ln -s gcc "${TOOLS}/bin/cc" &&
# Now we need to beat libsupc++ out of gcc (which uClibc++ needs to build).
# But don't want to build the whole of libstdc++-v3 because
# A) we're using uClibc++ instead,  B) the build breaks.
make -j $CPUS configure-target-libstdc++-v3 &&
cd "$CROSS_TARGET"/libstdc++-v3/libsupc++ &&
make -j $CPUS &&
mv .libs/libsupc++.a "$TOOLS"/lib &&
cd ../../../..

cleanup gcc-core build-gcc

# Move the gcc internal libraries and headers somewhere sane, and
# build and install gcc wrapper script.

mkdir -p "${TOOLS}"/gcc &&
mv "${TOOLS}"/lib/gcc/*/*/include "${TOOLS}"/gcc/include &&
mv "${TOOLS}"/lib/gcc/*/* "${TOOLS}"/gcc/lib &&
mv "${TOOLS}/bin/gcc" "${TOOLS}/bin/rawgcc" &&
"${ARCH}-gcc" "${SOURCES}"/toys/gcc-uClibc.c -Os -s -o "${TOOLS}/bin/gcc" \
  -DGCC_UNWRAPPED_NAME='"rawgcc"' -DGIMME_AN_S &&

# Wrap C++
mv "${TOOLS}/bin/g++" "${TOOLS}/bin/rawg++" &&
ln "${TOOLS}/bin/gcc" "${TOOLS}/bin/g++" &&
rm "${TOOLS}/bin/c++" &&
ln -s g++ "${TOOLS}/bin/c++"

cleanup "${TOOLS}"/{lib/gcc,gcc/lib/install-tools,bin/${ARCH}-unknown-*}

# Tell future packages to link against the libraries in mini-native,
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

# Build and install make

setupfor make
CC="${ARCH}-gcc" ./configure --prefix="${TOOLS}" --build="${CROSS_HOST}" \
  --host="${CROSS_TARGET}" &&
make -j $CPUS &&
make -j $CPUS install &&
cd ..

cleanup make

# Remove the busybox /bin/sh link so the bash install doesn't get upset.

rm "$TOOLS"/bin/sh

# Build and install bash.  (Yes, this is an old version.  I prefer it.)
# I plan to replace it with toysh anyway.

setupfor bash
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
ln -s bash "${TOOLS}/bin/sh" &&
cd ..

cleanup bash

setupfor distcc
./configure --host="${ARCH}" --prefix="${TOOLS}" --with-included-popt &&
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

"${ARCH}-gcc" "${SOURCES}/toys/hello.c" -Os -s -o "${TOOLS}/bin/hello-dynamic"  &&
"${ARCH}-gcc" "${SOURCES}/toys/hello.c" -Os -s -static -o "${TOOLS}/bin/hello-static"

[ $? -ne 0 ] && dienow

# End of NATIVE_NOTOOLCHAIN

fi

# Clean up and package the result

"${ARCH}-strip" "${TOOLS}"/{bin/*,sbin/*,libexec/gcc/*/*/*}

echo -n creating mini-native-"${ARCH}".tar.bz2 &&
cd "${BUILD}" &&
{ tar cjvf "mini-native-${ARCH}.tar.bz2" "mini-native-${ARCH}" || dienow
} | dotprogress

# Color back to normal
echo -e "\e[0mBuild complete"
