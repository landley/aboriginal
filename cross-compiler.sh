#!/bin/sh

# Get lots of predefined environment variables and shell functions.

source include.sh

mkdir -p "${CROSS}" || dienow

# Orange
echo -e "\e[33m"

# Build and install binutils

setupfor binutils build-binutils
"${CURSRC}/configure" --prefix="${CROSS}" --host=${CROSS_HOST} \
	--target=${CROSS_TARGET} --with-lib-path=lib --disable-nls \
	--disable-shared --disable-multilib --program-prefix="${ARCH}-" \
	$BINUTILS_FLAGS &&
make configure-host &&
make &&
make install &&
cd .. &&
mkdir -p "${CROSS}/include" &&
cp binutils-*/include/libiberty.h "${CROSS}/include" &&
$CLEANUP binutils-* build-binutils

[ $? -ne 0 ] && dienow

# Build and install gcc

setupfor gcc-core build-gcc gcc-
AR_FOR_TARGET="${ARCH}-ar" "${CURSRC}/configure" $GCC_FLAGS \
	--prefix="${CROSS}" --host=${CROSS_HOST} --target=${CROSS_TARGET} \
	--enable-languages=c --disable-threads --disable-multilib \
	--disable-nls --disable-shared $GCC_FLAGS --program-prefix="${ARCH}-" &&
make all-gcc &&
make install-gcc &&
cd .. &&

echo Fixup toolchain... &&

# Move the gcc internal libraries and headers somewhere sane.

mkdir -p "${CROSS}"/gcc &&
mv "${CROSS}"/lib/gcc/*/*/include "${CROSS}"/gcc/include &&
mv "${CROSS}"/lib/gcc/*/* "${CROSS}"/gcc/lib &&
$CLEANUP "${CURSRC}" build-gcc "${CROSS}"/{lib/gcc,gcc/lib/install-tools} &&

# Build and install gcc wrapper script.

cd "${CROSS}"/bin &&
mv "${ARCH}-gcc" gcc-unwrapped &&
gcc "${TOP}"/sources/toys/gcc-uClibc.c -Os -s -o "${ARCH}-gcc"

[ $? -ne 0 ] && dienow

# Install the linux kernel, and kernel headers.

setupfor linux
# Install Linux kernel headers (for use by uClibc).
make headers_install ARCH="${KARCH}" INSTALL_HDR_PATH="${CROSS}" &&
cd .. &&
$CLEANUP linux-*

[ $? -ne 0 ] && dienow

# Build and install uClibc

setupfor uClibc
cp "${WORK}"/config-uClibc .config &&
(yes "" | make CROSS="${ARCH}-" oldconfig) > /dev/null &&
make CROSS="${ARCH}-" KERNEL_HEADERS="${CROSS}/include" PREFIX="${CROSS}/" \
	RUNTIME_PREFIX=/ DEVEL_PREFIX=/ all install_runtime install_dev &&
# This needs to be built with the native compiler.  Since uClibc uses $CROSS
# internally, we have to blank it to avoid confusing them.
#CROSS= make KERNEL_HEADERS="${CROSS}/include" \
#	RUNTIME_PREFIX="${CROSS}/" DEVEL_PREFIX="${CROSS}/" install_utils &&
cd .. &&
$CLEANUP uClibc*

[ $? -ne 0 ] && dienow

# Skip this part if we're doing a short build.

if [ -z "${BUILD_SHORT}" ]
then

# Build qemu
setupfor qemu &&
./configure --disable-gcc-check --prefix="${CROSS}" &&
make &&
make install &&
cd .. &&
$CLEANUP qemu-*

# A quick hello world program to test the cross-compiler out.

cat > "$WORK"/hello.c << 'EOF' &&
#include <stdio.h>

int main(int argc, char *argv[])
{
  printf("Hello world!\n");
  return 0;
}
EOF

# Build hello.c dynamic, then static, to verify header/library paths.

"${ARCH}-gcc" -Os "$WORK"/hello.c -o "$WORK"/hello &&
"${ARCH}-gcc" -Os -static "$WORK"/hello.c -o "$WORK"/hello &&
[ x"$(qemu-"${KARCH}" "${WORK}"/hello)" == x"Hello world!" ] &&
echo Cross-toolchain seems to work.

[ $? -ne 0 ] && dienow

fi

cat > "${CROSS}"/README << EOF &&
Cross compiler for $ARCH
From http://landley.net/code/firmware

To use: Add the "bin" directory to your \$PATH, and use "$ARCH-gcc" as
your compiler.

The syntax used to build the Linux kernel is:

  make ARCH=${KARCH} CROSS_COMPILE=${ARCH}-

EOF

# Strip everything

cd "$CROSS"
for i in `find bin -type f` `find "$CROSS_TARGET" -type f`
do
  strip "$i" 2> /dev/null
done
#for i in `find lib -type f` `find gcc/lib -type f`
#do
#  "${ARCH}-strip" "$i" 2> /dev/null
#done

echo -n creating cross-compiler-"${ARCH}".tar.bz2 &&
cd "${TOP}"
{ tar cjvCf build cross-compiler-"${ARCH}".tar.bz2 cross-compiler-"${ARCH}" ||
  dienow
} | dotprogress

[ $? -ne 0 ] && dienow

echo -e "\e[32mCross compiler toolchain build complete.\e[0m"
