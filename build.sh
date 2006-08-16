#!/bin/sh

# Memo: How should I pass this in?

ARCH=x86_64

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

# Extract package $1, use work directory $2 (or $1 if no $2)

function setupfor()
{
  echo "=== Building $1"
  echo -n "Extracting"
  cd "${WORK}" &&
  { tar xvjf "${SOURCES}/${STAGE}/$1".tar.bz2 || dienow
  } | dotprogress
  if [ -z "$2" ]
  then
    cd "$1"* || dienow
  else
    mkdir "$2"
    cd "$2" || dienow
  fi
  export CURSRC="${WORK}/$1"*
  [ ! -d "${CURSRC}" ] && dienow
}

# Setup

umask 022
unset CFLAGS CXXFLAGS

# Find/create directories

TOP=`pwd`
export SOURCES="${TOP}/sources"
export CROSS="${TOP}/build/cross-compiler"
export WORK="${TOP}/build/temp"
mkdir -p "${CROSS}" "${WORK}"

[ $? -ne 0 ] && dienow

# For bash: check the $PATH for new executables added after startup.
set +h
# Put the cross compiler in the path
export PATH=${CROSS}/bin:/bin:/usr/bin

# Which platform are we building for?

[ "$ARCH" == x86_64 ] && export BUILD64="-m64"
export CROSS_HOST=i686-pc-linux-gnu
export CROSS_TARGET=${ARCH}-unknown-linux-gnu

export STAGE=build-cross

if false
then

echo === Install linux-headers.

setupfor linux-headers
#cd "${WORK}"
#tar xvjf "${SOURCES}"/build-cross/linux-headers.tar.bz2 &&
#cd linux-headers* &&
mkdir "${CROSS}"/include &&
mv include/asm-${ARCH} "${CROSS}"/include/asm &&
mv include/asm-generic "${CROSS}"/include &&
mv include/linux "${CROSS}"/include &&
cd ..
rm -rf linux-headers*

[ $? -ne 0 ] && dienow

setupfor binutils build-binutils
"${CURSRC}/configure" --prefix="${CROSS}" --host=${CROSS_HOST} \
	--target=${CROSS_TARGET} --with-lib-path=lib --disable-nls \
	--disable-shared --enable-64-bit-bfd --disable-multilib &&
make configure-host &&
make &&
make install &&
cd .. &&
cp binutils-*/include/libiberty.h "${CROSS}/include" &&
rm -rf binutils-* build-binutils

[ $? -ne 0 ] && dienow


setupfor gcc-core build-gcc
# Remove /usr/libexec/gcc and /usr/lib/gcc from gcc's search path.  (Don't grab
# random host libraries when cross-compiling, it's not polite.)
sed -ie 's/standard_exec_prefix_//;T;N;d' "${CURSRC}/gcc/gcc.c" &&
# Adjust StartFile Spec to point to cross libraries.
#echo -e "\n#undef STARTFILE_PREFIX_SPEC\n#define STARTFILE_PREFIX_SPEC \"${CROSS}/lib/\"" >> ../gcc-*/gcc/config/linux.h &&
# Adjust preprocessor's default search path
#sed -ire "s@(^CROSS_SYSTEM_HEADER_DIR =).*@\1 ${CROSS}/include@g" ../gcc-*/gcc/Makefile.in &&
"${CURSRC}/configure" --prefix="${CROSS}" --host=${CROSS_HOST} \
	--target=${CROSS_TARGET} --with-local-prefix="${CROSS}" \
	--disable-multilib --disable-nls --disable-shared --disable-threads \
	--enable-languages=c &&
make all-gcc &&
make install-gcc &&
cd .. &&
rm -rf "${CURSRC}" build-gcc

fi

[ $? -ne 0 ] && dienow
