#!/bin/sh

# Get lots of predefined environment variables and shell functions.

source include.sh
TOOLS="${NATIVE}/tools"

mkdir -p "${TOOLS}/bin" || dienow

# Build qemu
setupfor qemu &&
./configure --disable-gcc-check --prefix="${NATIVE}" &&
make &&
make install &&
cd .. &&
$CLEANUP qemu-*

[ $? -ne 0 ] && dienow

setupfor linux
# Install Linux kernel headers (for use by uClibc).
make headers_install ARCH="${KARCH}" INSTALL_HDR_PATH="${TOOLS}" &&
# build bootable kernel for target
mv "${WORK}/config-linux" .config &&
(yes "" | make ARCH="${KARCH}" oldconfig) &&
make ARCH="${KARCH}" CROSS_COMPILE="${ARCH}-" &&
cp "${KERNEL_PATH}" "${NATIVE}/zImage-${ARCH}" &&
cd .. &&
$CLEANUP linux-*

[ $? -ne 0 ] && dienow

# Build and install busybox

setupfor busybox
make defconfig &&
make CONFIG_STATIC=y CROSS_COMPILE="${ARCH}-" &&
cp busybox "${TOOLS}/bin"
[ $? -ne 0 ] && dienow
for i in $(sed 's@.*/@@' busybox.links)
do
  ln -s busybox "${TOOLS}/bin/$i" || dienow
done
cd .. &&
$CLEANUP busybox

[ $? -ne 0 ] && dienow

# Build and install native binutils

setupfor binutils build-binutils
CC="${ARCH}"-gcc AR="${ARCH}"-ar "${CURSRC}/configure" --prefix="${TOOLS}" \
  --build="${CROSS_HOST}" --host=${CROSS_TARGET} --target=${CROSS_TARGET} \
  --disable-nls --disable-shared --disable-multilib $BINUTILS_FLAGS &&
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
CC="${ARCH}-gcc" AS="${ARCH-gcc}" LD="${ARCH}-ld" "${CURSRC}/configure" \
  --prefix="${TOOLS}" --disable-multilib \
  --build="${CROSS_HOST}" --host="${CROSS_TARGET}" --target="${CROSS_TARGET}" \
  --enable-long-long --enable-c99 --enable-shared --enable-threads=posix \
  --enable-__cxa_atexit --disable-nls --enable-languages=c,c++ \
  --disable-libstdcxx-pch &&
cd "${WORK}"/build-gcc &&

make all-gcc  && # CC_FOR_TARGET="${ARCH}-gcc" AS_FOR_TARGET="${ARCH}-as" \
#     LD_FOR_TARGET="${ARCH}-ld" all-gcc &&
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

mv "${TOOLS}/bin/${ARCH}-gcc" "${TOOLS}/bin/gcc-unwrapped" &&
gcc "${TOP}"/sources/toys/gcc-uClibc.c -Os -s -o "${TOOLS}/bin/${ARCH}-gcc"

[ $? -ne 0 ] && dienow

exit 0

# Install the linux kernel, and kernel headers.

setupfor linux
# Configure kernel
##mv "${WORK}"/config-linux .config &&
##(yes "" | make ARCH="${KARCH}" oldconfig) &&
# Install Linux kernel headers (for use by uClibc).
make headers_install ARCH="${KARCH}" INSTALL_HDR_PATH="${CROSS}" &&
# Build bootable kernel for target.
##make ARCH="${KARCH}" CROSS_COMPILE="${CROSS_TARGET}"- &&
##cp "${KERNEL_PATH}" "${CROSS}"/zImage &&
cd .. &&
$CLEANUP linux-*

[ $? -ne 0 ] && dienow

# Build and install uClibc

setupfor uClibc
cp "${WORK}"/config-uClibc .config &&
(yes "" | make CROSS="${CROSS_TARGET}"- oldconfig) &&
make CROSS="${CROSS_TARGET}"- KERNEL_SOURCE="${CROSS}" &&
#make CROSS="${CROSS_TARGET}"- utils &&
# The kernel headers are already installed, but uClibc's install will try to
# be "helpful" and copy them over themselves, at which point hilarity ensues.
# Make it not do that.
rm include/{asm,asm-generic,linux} &&
make CROSS="${CROSS_TARGET}"- KERNEL_SOURCE="${CROSS}"/ \
	RUNTIME_PREFIX="${CROSS}"/ DEVEL_PREFIX="${CROSS}"/ \
	install_runtime install_dev &&
# The uClibc build uses ./include instead of ${CROSS}/include, so the symlinks
# need to come back.  (Yes, it links against the _headers_ from the source,
# but against the _libraries_ from the destination.  Hence needing to install
# libc.so before building utils.)
ln -s "${CROSS}"/include/linux include/linux &&
ln -s "${CROSS}"/include/asm include/asm &&
ln -s "${CROSS}"/include/asm-generic include/asm-generic &&
make CROSS=${CROSS_TARGET}- RUNTIME_PREFIX="${CROSS}"/ install_utils &&
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

"$GCCNAME" -Os "$WORK"/hello.c -o "$WORK"/hello &&
"$GCCNAME" -Os -static "$WORK"/hello.c -o "$WORK"/hello &&
[ x"$(qemu-"${KARCH}" "${WORK}"/hello)" == x"Hello world!" ] &&
echo Cross-toolchain seems to work.

[ $? -ne 0 ] && dienow

# Change the FSF's crazy names to something reasonable.

cd "${CROSS}"/bin &&
for i in "${ARCH}"-*
do
  strip "$i"
  mv "$i" "${ARCH}"-"$(echo "$i" | sed 's/.*-//')"
done

cat > "${CROSS}"/README << "EOF" &&
Cross compiler for $ARCH
From http://landley.net/code/firmware

To use: Add the \"bin\" directory to your \$PATH, and use \"$ARCH-gcc\" as
your compiler.

The syntax used to build the Linux kernel is:

  make ARCH="${KARCH}" CROSS_COMPILE="${ARCH}"-

EOF

# Tar up the cross compiler.
cd "${TOP}"
tar cjvCf build cross-compiler-"${ARCH}".tar.bz2 cross-compiler-"${ARCH}" &&

[ $? -ne 0 ] && dienow
