Build binutils, c wrapper, and uClibc++

# Build binutils, which provides the linker and assembler and such.

# PROGRAM_PREFIX affects the name of the generated tools, ala "${ARCH}-".

setupfor binutils

# The binutils ./configure stage is _really_stupid_, and we need to define
# lots of environment variables to make it behave.

function configure_binutils()
{
  "$CURSRC/configure" --prefix="$STAGE_DIR" \
    --build="$CROSS_HOST" --host="$FROM_HOST" --target="$CROSS_TARGET" \
    --disable-nls --disable-shared --disable-multilib --disable-werror \
    --with-lib-path=lib --program-prefix="$PROGRAM_PREFIX" $BINUTILS_FLAGS

  [ $? -ne 0 ] && dienow
}

if [ -z "$FROM_ARCH" ]
then
  # Create a simple cross compiler, from this host to target $ARCH.
  # This has no prerequisites.

  # The binutils ./configure stage is _really_stupid_.  Define lots of
  # environment variables to make it behave.

  AR=ar AS=as LD=ld NM=nm OBJDUMP=objdump OBJCOPY=objcopy configure_binutils
else
  # Canadian cross for an arbitrary host/target.  The new compiler will run
  # on $FROM_ARCH as its host, and build executables for $ARCH as its target.
  # (Use host==target to produce a native compiler.)  Doing this requires
  # existing host ($FROM_ARCH) _and_ target ($ARCH) cross compilers as
  # prerequisites.

  AR="${FROM_ARCH}-ar" CC="${FROM_ARCH}-cc" configure_binutils
fi

# Now that it's configured, build and install binutils

make -j $CPUS configure-host &&
make -j $CPUS CFLAGS="-O2 $STATIC_FLAGS" &&
make -j $CPUS install &&
mkdir -p "$STAGE_DIR/include" &&
cp "$CURSRC/include/libiberty.h" "$STAGE_DIR/include"

cleanup build-binutils

# Force gcc to build, largely against its will.

setupfor gcc-core build-gcc
setupfor gcc-g++ build-gcc gcc-core

# GCC tries to "help out in the kitchen" by screwing up the kernel include
# files.  Surgery with sed to cut out that horrible idea throw it away.

sed -i 's@^STMP_FIX.*@@' "${CURSRC}/gcc/Makefile.in" || dienow

# The gcc ./configure manages to make the binutils one look sane.  Again,
# wrap it so we can call it with different variables to beat sense out of it.

function configure_gcc()
{
  "$CURSRC/configure" --target="$CROSS_TARGET" --prefix="$STAGE_DIR" \
    --disable-multilib --disable-nls --enable-c99 --enable-long-long \
    --enable-__cxa_atexit --enable-languages=c,c++ --disable-libstdcxx-pch \
    --program-prefix="$PROGRAM_PREFIX" "$@" $GCC_FLAGS &&
  mkdir -p gcc &&
  ln -s `which ${CC_FOR_TARGET:-cc}` gcc/xgcc || dienow
}

if [ -z "$FROM_ARCH" ]
then
  # Produce a standard host->target cross compiler, which does not include
  # thread support or libgcc_s.so to make it depend on the host less.

  # The only prerequisite for this is binutils, above.  (It doesn't even
  # require a C library for the target to exist yet, which is good because you
  # have a chicken and egg problem otherwise.  What would you have compiled
  # that C library _with_?)

  AR_FOR_TARGET="${ARCH}-ar" configure_gcc \
    --disable-threads --disable-shared --host="$CROSS_HOST"
else
  # Canadian cross a compiler to run on $FROM_ARCH as its host and output
  # binaries for $ARCH as its target.

  # GCC has some deep assumptions here, which are wrong.  Lots of redundant
  # corrections are required to make it stop.

  CC="${FROM_ARCH}-cc" AR="${FROM_ARCH}-ar" AS="${FROM_ARCH}-as" \
    LD="${FROM_ARCH}-ld" NM="${FROM_ARCH}-nm" \
    CC_FOR_TARGET="${ARCH}-cc" AR_FOR_TARGET="${ARCH}-ar" \
    NM_FOR_TARGET="${ARCH}-nm" GCC_FOR_TARGET="${ARCH}-cc" \
    AS_FOR_TARGET="${ARCH}-as" LD_FOR_TARGET="${ARCH}-ld" \
    CXX_FOR_TARGET="${ARCH}-c++" \
    ac_cv_path_AR_FOR_TARGET="${ARCH}-ar" \
    ac_cv_path_RANLIB_FOR_TARGET="${ARCH}-ranlib" \
    ac_cv_path_NM_FOR_TARGET="${ARCH}-nm" \
    ac_cv_path_AS_FOR_TARGET="${ARCH}-as" \
    ac_cv_path_LD_FOR_TARGET="${ARCH}-ld" \
    configure_gcc --enable-threads=posix --enable-shared \
      --build="$CROSS_HOST" --host="$CROSS_TARGET"
fi

# Now that it's configured, build and install gcc

make -j $CPUS configure-host &&
make -j $CPUS all-gcc LDFLAGS="$STATIC_FLAGS" &&

# Work around gcc bug; we disabled multilib but it doesn't always notice.

ln -s lib "$STAGE_DIR/lib64" &&
make -j $CPUS install-gcc &&
rm "$STAGE_DIR/lib64" &&
ln -s "${PROGRAM_PREFIX}gcc" "$STAGE_DIR/bin/${PROGRAM_PREFIX}cc" || dienow

# Now we need to beat libsupc++ out of gcc (which uClibc++ needs to build).
# But don't want to build the whole of libstdc++-v3 because
# A) we're using uClibc++ instead,  B) the build breaks.

if [ ! -z "$FROM_ARCH" ]
then
  # The libsupc++ ./configure dies if run after the simple cross compiling
  # ./configure, because gcc's build system is overcomplicated crap.  So
  # skip the uClibc++ build first time around.  We still build C++ support
  # in gcc because we need it to canadian cross build uClibc++ later.

  make -j $CPUS configure-target-libstdc++-v3 &&
  cd "$CROSS_TARGET"/libstdc++-v3/libsupc++ &&
  make -j $CPUS &&
  mv .libs/libsupc++.a "$STAGE_DIR"/lib || dienow
fi

# We're done with that source and could theoretically cleanup gcc-core and
# build-gcc here, but we still need the timestamps if we do binary package
# tarballs.

function build_ccwrap()
{
  # build and install gcc wrapper script.

  TEMP="${FROM_ARCH}-cc"
  [ -z "$FROM_ARCH" ] && TEMP="$CC"

  mv "$STAGE_DIR/bin/${PROGRAM_PREFIX}"{gcc,rawgcc} &&
  "$TEMP" "$SOURCES/toys/ccwrap.c" -Os -s \
    -o "$STAGE_DIR/bin/${PROGRAM_PREFIX}gcc" "$@" $STATIC_FLAGS \
    -DGCC_UNWRAPPED_NAME='"'"${PROGRAM_PREFIX}rawgcc"'"' &&

  # Move the gcc internal libraries and headers somewhere sane

  mkdir -p "$STAGE_DIR"/gcc &&
  mv "$STAGE_DIR"/lib/gcc/*/*/include "$STAGE_DIR"/gcc/include &&
  mv "$STAGE_DIR"/lib/gcc/*/* "$STAGE_DIR"/gcc/lib &&

  # Rub gcc's nose in the binutils output.  (It's RIGHT THERE!  Find it!)

  cd "$STAGE_DIR"/libexec/gcc/*/*/ &&
  cp -s "../../../../$CROSS_TARGET/bin/"* . &&

  # Wrap C++ too.

  mv "$STAGE_DIR/bin/${PROGRAM_PREFIX}"{g++,rawg++} &&
  rm "$STAGE_DIR/bin/${PROGRAM_PREFIX}c++" &&
  ln -s "$STAGE_DIR/bin/${PROGRAM_PREFIX}"{rawg++,rawc++} &&
  ln -s "$STAGE_DIR/bin/${PROGRAM_PREFIX}"{gcc,g++} &&
  ln -s "$STAGE_DIR/bin/${PROGRAM_PREFIX}"{gcc,c++} || dienow
}

if [ -z "$FROM_ARCH" ]
then
  build_ccwrap
else
  build_ccwrap -DGIMME_AN_S
fi

mv "$WORK"/{gcc-core,gcc}
PACKAGE=gcc cleanup build-gcc "${STAGE_DIR}"/{lib/gcc,{libexec/gcc,gcc/lib}/install-tools,bin/${ARCH}-unknown-*}
