#!/bin/bash

# Get lots of predefined environment variables and shell functions.

source sources/include.sh || exit 1

CROSS="${BUILD}/cross-compiler-${ARCH}"

check_for_base_arch cross-compiler || exit 0

echo -e "$CROSS_COLOR"
echo "=== Building cross compiler"

rm -rf "${CROSS}"
mkdir -p "${CROSS}" || dienow

# Build and install binutils

setupfor binutils build-binutils &&
AR=ar AS=as LD=ld NM=nm OBJDUMP=objdump OBJCOPY=objcopy \
	"${CURSRC}/configure" --prefix="${CROSS}" --host=${CROSS_HOST} \
	--target=${CROSS_TARGET} --with-lib-path=lib --disable-nls \
	--disable-shared --disable-multilib --program-prefix="${ARCH}-" \
	--disable-werror $BINUTILS_FLAGS &&
make -j $CPUS configure-host &&
make -j $CPUS CFLAGS="-O2 $STATIC_FLAGS" &&
make -j $CPUS install &&
cd .. &&
mkdir -p "${CROSS}/include" &&
cp binutils/include/libiberty.h "${CROSS}/include"

cleanup binutils build-binutils

# Build and install gcc

setupfor gcc-core build-gcc &&
setupfor gcc-g++ build-gcc gcc-core &&
AR_FOR_TARGET="${ARCH}-ar" "${CURSRC}/configure" \
  --prefix="${CROSS}" --host=${CROSS_HOST} --target=${CROSS_TARGET} \
  --enable-languages=c,c++ --enable-long-long --enable-c99 \
  --disable-shared --disable-threads --disable-nls --disable-multilib \
  --enable-__cxa_atexit --disable-libstdcxx-pch \
  --program-prefix="${ARCH}-" $GCC_FLAGS &&

# Try to convince gcc build process not to rebuild itself with itself.
mkdir -p gcc &&
ln -s `which gcc` gcc/xgcc &&

make -j $CPUS all-gcc LDFLAGS="$STATIC_FLAGS" &&
make -j $CPUS install-gcc &&
cd ..

cleanup gcc-core build-gcc

echo Fixup toolchain... &&

# Move the gcc internal libraries and headers somewhere sane.

mkdir -p "${CROSS}"/gcc &&
mv "${CROSS}"/lib/gcc/*/*/include "${CROSS}"/gcc/include &&
mv "${CROSS}"/lib/gcc/*/* "${CROSS}"/gcc/lib &&
ln -s ${CROSS_TARGET} ${CROSS}/tools &&
ln -sf ../../../../tools/bin/ld  ${CROSS}/libexec/gcc/*/*/collect2 &&

# Build and install gcc wrapper script.

cd "${CROSS}"/bin &&
mv "${ARCH}-gcc" "$ARCH-rawgcc" &&
$CC $STATIC_FLAGS -Os -s "${SOURCES}"/toys/ccwrap.c -o "${ARCH}-gcc" \
  -DGCC_UNWRAPPED_NAME='"'"$ARCH"-rawgcc'"' &&
ln -s "${ARCH}-gcc" "${ARCH}-cc" &&

# Wrap C++

mv "${ARCH}-g++" "${ARCH}-rawg++" &&
rm "${ARCH}-c++" &&
ln -s "${ARCH}-g++" "${ARCH}-rawc++" &&
ln -s "${ARCH}-gcc" "${ARCH}-g++" &&
ln -s "${ARCH}-gcc" "${ARCH}-c++"

cleanup "${CROSS}"/{lib/gcc,{libexec/gcc,gcc/lib}/install-tools}

# Install kernel headers.

setupfor linux &&
# Install Linux kernel headers (for use by uClibc).
make -j $CPUS headers_install ARCH="${KARCH}" INSTALL_HDR_PATH="${CROSS}" &&
# This makes some very old package builds happy.
ln -s ../sys/user.h "${CROSS}/include/asm/page.h" &&
cd ..

cleanup linux

# Build and install uClibc

setupfor uClibc
make CROSS= KCONFIG_ALLCONFIG="$(getconfig uClibc)" allnoconfig &&
make CROSS="${ARCH}-" KERNEL_HEADERS="${CROSS}/include" PREFIX="${CROSS}/" \
     RUNTIME_PREFIX=/ DEVEL_PREFIX=/ -j $CPUS $VERBOSITY \
     install hostutils || dienow
for i in $(cd utils; ls *.host | sed 's/\.host//')
do
  cp utils/"$i".host "$CROSS/bin/$ARCH-$i" || dienow
done
cd ..

cleanup uClibc

cat > "${CROSS}"/README << EOF &&
Cross compiler for $ARCH
From http://impactlinux.com/fwl

To use: Add the "bin" subdirectory to your \$PATH, and use "$ARCH-gcc" as
your compiler.

The syntax used to build the Linux kernel is:

  make ARCH=${KARCH} CROSS_COMPILE=${ARCH}-

EOF

# Strip the binaries

cd "$CROSS"
for i in `find bin -type f` `find "$CROSS_TARGET" -type f`
do
  strip "$i" 2> /dev/null
done

# Tar it up

create_stage_tarball cross-compiler

# A quick hello world program to test the cross-compiler out.
# Build hello.c dynamic, then static, to verify header/library paths.

echo "Sanity test: building Hello World."

"${ARCH}-gcc" -Os "${SOURCES}/toys/hello.c" -o "$WORK"/hello &&
"${ARCH}-gcc" -Os -static "${SOURCES}/toys/hello.c" -o "$WORK"/hello &&
if [ ! -z "$CROSS_SMOKE_TEST" ] && which qemu-"${QEMU_TEST}" > /dev/null
then
  [ x"$(qemu-"${QEMU_TEST}" "${WORK}"/hello)" == x"Hello world!" ] &&
  echo Cross-toolchain seems to work.
fi

[ $? -ne 0 ] && dienow

echo -e "\e[32mCross compiler toolchain build complete.\e[0m"
