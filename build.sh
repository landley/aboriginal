#!/bin/sh

# Memo: How should I pass this in?

ARCH="$(echo "$1" | sed 's@.*/@@')"
if [ ! -f sources/configs/"$1" ]
then
  echo "Usage: $0 ARCH"
  echo "Supported architectures: $(cd sources/configs && ls)"
  exit 1
fi

CLEANUP="rm -rf"

function dienow()
{
  echo "Exiting due to errors"
  exit 1
}


function dotprogress()
{
  x=0
  while read i
  do
    x=$[$x + 1]
    if [[ "$x" -eq 25 ]]
    then
      x=0
      echo -n .
    fi
  done
  echo
}

# Extract package $1, use work directory $2 (or $1 if no $2), use source
# directory $3 (or $1 if no $3)

function setupfor()
{
  FILE="${SOURCES}/${STAGE}/$1"
  if [ -f "${FILE}".tar.bz2 ]
  then
    FILE="${FILE}".tar.bz2
    DECOMPRESS="j"
  else
    FILE="${FILE}".tar.gz
    DECOMPRESS="z"
  fi
  echo "=== Building $1"
  echo -n "Extracting"
  cd "${WORK}" &&
  { tar xv${DECOMPRESS}f "$FILE" || dienow
  } | dotprogress
  if [ -z "$2" ]
  then
    cd "$1"* || dienow
  else
    mkdir "$2"
    cd "$2" || dienow
  fi
  export CURSRC="$1"
  [ ! -z "$3" ] && CURSRC="$3"
  export CURSRC=`echo "${WORK}/${CURSRC}"*`
  [ ! -d "${CURSRC}" ] && dienow
}

# Setup

umask 022
unset CFLAGS CXXFLAGS

# Find/create directories

TOP=`pwd`
export SOURCES="${TOP}/sources"
export CROSS="${TOP}/build/cross-compiler-$ARCH"
export WORK="${TOP}/build/temp"
mkdir -p "${CROSS}" "${WORK}"

[ $? -ne 0 ] && dienow

# For bash: check the $PATH for new executables added after startup.
set +h
# Put the cross compiler in the path
export PATH=${CROSS}/bin:"$PATH"

# Which platform are we building for?

export CROSS_HOST=i686-pc-linux-gnu
export CROSS_TARGET=${ARCH}-unknown-linux-gnu

export STAGE=build-cross

# Import the config for this arch.

. sources/configs/"$ARCH"

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

# Move the gcc internal libraries and headers somewhere sane.

mkdir -p "${CROSS}"/gcc &&
mv "${CROSS}"/lib/gcc/*/*/include "${CROSS}"/gcc/include &&
mv "${CROSS}"/lib/gcc/*/* "${CROSS}"/gcc/lib &&
$CLEANUP "${CURSRC}" build-gcc "${CROSS}"/{lib/gcc,gcc/lib/install-tools} &&

# Build and install gcc wrapper script.

GCCNAME="$(echo "${CROSS}"/bin/*-gcc)" &&
mv "$GCCNAME" "${CROSS}"/bin/gcc-unwrapped &&
gcc "${TOP}"/sources/toys/gcc-uClibc.c -Os -s -o "$GCCNAME"

[ $? -ne 0 ] && dienow

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
