#!/bin/sh

# Get lots of predefined environment variables and shell functions.

source include.sh

mkdir -p "${CROSS}" || dienow

# Build and install binutils

setupfor binutils build-binutils
"${CURSRC}/configure" --prefix="${CROSS}" --host=${CROSS_HOST} \
	--target=${CROSS_TARGET} --with-lib-path=lib --disable-nls \
	--disable-shared --disable-multilib $BINUTILS_FLAGS &&
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
"${CURSRC}/configure" --prefix="${CROSS}" --host=${CROSS_HOST} \
	--target=${CROSS_TARGET} --disable-threads --enable-languages=c \
	--disable-multilib --disable-nls --disable-shared $GCC_FLAGS
	#--with-local-prefix="${CROSS}" \
	# --enable-languages=c,c++ --enable-__cxa_atexit --enable-c99 \
	# --enable-long-long --enable-threads=posix &&
make all-gcc &&
make install-gcc &&
cd .. &&

echo Fixup toolchain... &&

# Move the gcc internal libraries and headers somewhere sane.

mkdir -p "${CROSS}"/gcc &&
mv "${CROSS}"/lib/gcc/*/*/include "${CROSS}"/gcc/include &&
mv "${CROSS}"/lib/gcc/*/* "${CROSS}"/gcc/lib &&
$CLEANUP "${CURSRC}" build-gcc "${CROSS}"/{lib/gcc,gcc/lib/install-tools} &&

# Change the FSF's crazy names to something reasonable.

cd "${CROSS}"/bin &&
for i in "${CROSS_TARGET}"-*
do
  strip "$i" &&
  mv "$i" "${ARCH}"-"$(echo "$i" | sed 's/.*-//')"
done &&

# Build and install gcc wrapper script.

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
make CROSS="${ARCH}-" KERNEL_HEADERS="${CROSS}/include" \
	RUNTIME_PREFIX="${CROSS}/" DEVEL_PREFIX="${CROSS}/" \
	all install_runtime install_dev install_utils &&
cd .. &&
$CLEANUP uClibc*

[ $? -ne 0 ] && dienow

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

cat > "${CROSS}"/README << EOF &&
Cross compiler for $ARCH
From http://landley.net/code/firmware

To use: Add the "bin" directory to your \$PATH, and use "$ARCH-gcc" as
your compiler.

The syntax used to build the Linux kernel is:

  make ARCH=${KARCH} CROSS_COMPILE=${ARCH}-

EOF

echo creating cross-compiler-"${ARCH}".tar.bz2 &&
cd "${TOP}"
{ tar cjvCf build cross-compiler-"${ARCH}".tar.bz2 cross-compiler-"${ARCH}" ||
  dienow
} | dotprogress

[ $? -ne 0 ] && dienow

echo Cross compiler toolchain build complete.
