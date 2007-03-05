#!/bin/sh

# Get lots of predefined environment variables and shell functions.

source include.sh

rm -rf "${NATIVE}"

TOOLS="${NATIVE}/tools"
mkdir -p "${TOOLS}/bin" || dienow

# Tell the wrapper script where to find the dynamic linker.
export UCLIBC_DYNAMIC_LINKER=/tools/lib/ld-uClibc.so.0
export UCLIBC_RPATH=/tools/lib

# Purple.  And why not?
echo -e "\e[35m"

# Build and install Linux kernel.

setupfor linux
# Install Linux kernel headers (for use by uClibc).
make headers_install ARCH="${KARCH}" INSTALL_HDR_PATH="${TOOLS}" &&
# build bootable kernel for target
make ARCH="${KARCH}" allnoconfig KCONFIG_ALLCONFIG="${WORK}/miniconfig-linux" &&
make ARCH="${KARCH}" CROSS_COMPILE="${ARCH}-" &&
cp "${KERNEL_PATH}" "${NATIVE}/zImage-${ARCH}" &&
cd .. &&
$CLEANUP linux-*

[ $? -ne 0 ] && dienow

# Build and install uClibc.  (We could just copy the one from the compiler
# toolchain, but this is cleaner.)

setupfor uClibc
cp "${WORK}"/config-uClibc .config &&
(yes "" | make CROSS="${ARCH}-" oldconfig) > /dev/null &&
make CROSS="${ARCH}-" KERNEL_HEADERS="${TOOLS}/include" PREFIX="${TOOLS}/" \
        RUNTIME_PREFIX=/ DEVEL_PREFIX=/ UCLIBC_LDSO_NAME=ld-uClibc \
        all install_runtime install_dev utils &&
# utils_install wants to put stuff in usr/bin instead of bin.
install -m 755 utils/{readelf,ldd,ldconfig} "${TOOLS}/bin" &&
cd .. &&
$CLEANUP uClibc*

[ $? -ne 0 ] && dienow

# Build and install busybox

setupfor busybox
make defconfig &&
make CROSS="${ARCH}-" &&
cp busybox "${TOOLS}/bin"
[ $? -ne 0 ] && dienow
for i in $(sed 's@.*/@@' busybox.links)
do
  ln -s busybox "${TOOLS}/bin/$i" || dienow
done
cd .. &&
$CLEANUP busybox-*

[ $? -ne 0 ] && dienow

if [ -z "${BUILD_SHORT}" ]
then

# Build and install native binutils

setupfor binutils build-binutils
CC="${ARCH}-gcc" AR="${ARCH}-ar" "${CURSRC}/configure" --prefix="${TOOLS}" \
  --build="${CROSS_HOST}" --host="${CROSS_TARGET}" --target="${CROSS_TARGET}" \
  --disable-nls --disable-shared --disable-multilib --program-prefix= \
  $BINUTILS_FLAGS &&
make configure-host &&
make &&
make install &&
cd .. &&
mkdir -p "${TOOLS}/include" &&
cp binutils-*/include/libiberty.h "${TOOLS}/include" &&
$CLEANUP binutils-* build-binutils

[ $? -ne 0 ] && dienow

# Build and install native gcc, with c++ support this time.

setupfor gcc-core build-gcc gcc-
echo -n "Adding c++" &&
(tar xvjCf "${WORK}" "${LINKDIR}/gcc-g++.tar.bz2" || dienow ) | dotprogress &&
# GCC tries to "help out in the kitchen" by screwing up the linux include
# files.  Cut out those bits with sed and throw them away.
sed -i 's@\./fixinc\.sh@-c true@' "${CURSRC}/gcc/Makefile.in" &&
# GCC has some deep assumptions about the name of the cross-compiler it should
# be using.  These assumptions are wrong, and lots of redundant corrections
# are required to make it stop.
CC="${ARCH}-gcc" GCC_FOR_TARGET="${ARCH}-gcc" CC_FOR_TARGET="${ARCH}-gcc" \
  AR="${ARCH}-ar" AR_FOR_TARGET="${ARCH}-ar" AS="${ARCH}-ar" LD="${ARCH}-ld" \
  NM="${ARCH}-nm" NM_FOR_TARGET="${ARCH}-nm" \
  "${CURSRC}/configure" --prefix="${TOOLS}" --disable-multilib \
  --build="${CROSS_HOST}" --host="${CROSS_TARGET}" --target="${CROSS_TARGET}" \
  --enable-long-long --enable-c99 --enable-shared --enable-threads=posix \
  --enable-__cxa_atexit --disable-nls --enable-languages=c,c++ \
  --disable-libstdcxx-pch --program-prefix="" &&
make all-gcc &&
make install-gcc &&
ln -s gcc "${TOOLS}/bin/cc" &&
cd .. &&
$CLEANUP gcc-* build-gcc

[ $? -ne 0 ] && dienow

# Move the gcc internal libraries and headers somewhere sane.

mkdir -p "${TOOLS}"/gcc &&
mv "${TOOLS}"/lib/gcc/*/*/include "${TOOLS}"/gcc/include &&
mv "${TOOLS}"/lib/gcc/*/* "${TOOLS}"/gcc/lib &&
$CLEANUP "${TOOLS}"/{lib/gcc,gcc/lib/install-tools} &&

# Build and install gcc wrapper script.

mv "${TOOLS}/bin/gcc" "${TOOLS}/bin/gcc-unwrapped" &&
"${ARCH}-gcc" "${TOP}"/sources/toys/gcc-uClibc.c -Os -s -o "${TOOLS}/bin/gcc"

[ $? -ne 0 ] && dienow

# Build and install make

setupfor make
CC="${ARCH}-gcc" ./configure --prefix="${TOOLS}" --build="${CROSS_HOST}" \
  --host="${CROSS_TARGET}" &&
make &&
make install &&
cd .. &&
$CLEANUP make-*

[ $? -ne 0 ] && dienow

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
CC="${ARCH}-gcc" ./configure --prefix="${TOOLS}" --build="${CROSS_HOST}" \
  --host="${CROSS_TARGET}" --cache-file=config.cache \
 --without-bash-malloc --disable-readline &&
make &&
make install &&
# Make bash the default shell.
ln -s bash "${TOOLS}/bin/sh" &&
cd .. &&
$CLEANUP bash-*

[ $? -ne 0 ] && dienow

# Put statically and dynamically linked hello world programs on there for
# test purposes.

"${ARCH}-gcc" "${SOURCES}/toys/hello.c" -Os -s -o "${TOOLS}/bin/hello-dynamic"  &&
"${ARCH}-gcc" "${SOURCES}/toys/hello.c" -Os -s -static -o "${TOOLS}/bin/hello-static" &&

[ $? -ne 0 ] && dienow

fi

# Clean up and package the result

"${ARCH}-strip" "${TOOLS}"/{bin/*,sbin/*,libexec/gcc/*/*/*}

cd "${BUILD}"
#echo -n "Creating tools.sqf"
#("${WORK}/mksquashfs" "${NATIVE}/tools" "tools-${ARCH}.sqf" \
#  -noappend -all-root -info || dienow) | dotprogress

echo -n creating mini-native-"${ARCH}".tar.bz2 &&
{ tar cjvf "mini-native-${ARCH}.tar.bz2" "mini-native-${ARCH}" || dienow
} | dotprogress

# Color back to normal
echo -e "\e[0mBuild complete"
