#!/bin/bash

# Get lots of predefined environment variables and shell functions.

source sources/include.sh || exit 1

# Parse the sources/targets/$1 directory

read_arch_dir "$1"

# If this target has a base architecture that's already been built, use that.

check_for_base_arch || exit 0

# Ok, we have work to do.  Announce start of stage.

echo -e "$CROSS_COLOR"
echo "=== Building $STAGE_NAME"

blank_tempdir "$STAGE_DIR"
blank_tempdir "$WORK"

# Build and install binutils

setupfor binutils build-binutils
AR=ar AS=as LD=ld NM=nm OBJDUMP=objdump OBJCOPY=objcopy \
	"${CURSRC}/configure" --prefix="${STAGE_DIR}" --host=${CROSS_HOST} \
	--target=${CROSS_TARGET} --with-lib-path=lib --disable-nls \
	--disable-shared --disable-multilib --program-prefix="${ARCH}-" \
	--disable-werror $BINUTILS_FLAGS &&
make -j $CPUS configure-host &&
make -j $CPUS CFLAGS="-O2 $STATIC_FLAGS" &&
make -j $CPUS install &&
mkdir -p "${STAGE_DIR}/include" &&
cp "$CURSRC/include/libiberty.h" "${STAGE_DIR}/include"

cleanup build-binutils

# Build and install gcc

setupfor gcc-core build-gcc &&
setupfor gcc-g++ build-gcc gcc-core &&
AR_FOR_TARGET="${ARCH}-ar" "${CURSRC}/configure" \
  --prefix="${STAGE_DIR}" --host=${CROSS_HOST} --target=${CROSS_TARGET} \
  --enable-languages=c,c++ --enable-long-long --enable-c99 \
  --disable-shared --disable-threads --disable-nls --disable-multilib \
  --enable-__cxa_atexit --disable-libstdcxx-pch \
  --program-prefix="${ARCH}-" $GCC_FLAGS &&

# Try to convince gcc build process not to rebuild itself with itself.
mkdir -p gcc &&
ln -s `which gcc` gcc/xgcc &&

make -j $CPUS all-gcc LDFLAGS="$STATIC_FLAGS" &&
make -j $CPUS install-gcc &&

# We're done with that source and could theoretically cleanup gcc-core and
# build-gcc here, but we still need the timestamps if we do binary packaging.

echo Fixup toolchain... &&

# Move the gcc internal libraries and headers somewhere sane.

mkdir -p "${STAGE_DIR}"/gcc &&
mv "${STAGE_DIR}"/lib/gcc/*/*/include "${STAGE_DIR}"/gcc/include &&
mv "${STAGE_DIR}"/lib/gcc/*/* "${STAGE_DIR}"/gcc/lib &&
ln -s ${CROSS_TARGET} ${STAGE_DIR}/tools &&
ln -sf ../../../../tools/bin/ld  ${STAGE_DIR}/libexec/gcc/*/*/collect2 &&

# Build and install gcc wrapper script.

cd "${STAGE_DIR}"/bin &&
mv "${ARCH}-gcc" "$ARCH-rawgcc" &&
$CC $STATIC_FLAGS -Os -s "${SOURCES}"/toys/ccwrap.c -o "${ARCH}-gcc" \
  -DGCC_UNWRAPPED_NAME='"'"$ARCH"-rawgcc'"' &&
ln -s "${ARCH}-gcc" "${ARCH}-cc" &&

# Wrap C++

mv "${ARCH}-g++" "${ARCH}-rawg++" &&
rm "${ARCH}-c++" &&
ln -s "${ARCH}-g++" "${ARCH}-rawc++" &&
ln -s "${ARCH}-gcc" "${ARCH}-g++" &&
ln -s "${ARCH}-gcc" "${ARCH}-c++" &&

# When tarring up individual binary packages, we want this one to be called
# "gcc" and that's not what we fed to setupfor, so rename it.

mv "$WORK"/gcc-core "$WORK"/gcc
PACKAGE=gcc cleanup build-gcc "${STAGE_DIR}"/{lib/gcc,{libexec/gcc,gcc/lib}/install-tools}

# Build uClibc

HOST_UTILS=1 . "$SOURCES"/sections/uClibc.sh

cat > "${STAGE_DIR}"/README << EOF &&
Cross compiler for $ARCH
From http://impactlinux.com/fwl

To use: Add the "bin" subdirectory to your \$PATH, and use "$ARCH-gcc" as
your compiler.

The syntax used to build the Linux kernel is:

  make ARCH=${KARCH} CROSS_COMPILE=${ARCH}-

EOF

# Strip the binaries

cd "$STAGE_DIR"
for i in `find bin -type f` `find "$CROSS_TARGET" -type f`
do
  strip "$i" 2> /dev/null
done

# Tar it up

create_stage_tarball

# A quick hello world program to test the cross compiler out.
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
