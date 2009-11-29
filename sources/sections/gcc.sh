# Build binutils, c wrapper, and uClibc++

# PROGRAM_PREFIX affects the name of the generated tools, ala "${ARCH}-".

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

# Work around gcc bug during the install: we disabled multilib but it doesn't
# always notice.

ln -s lib "$STAGE_DIR/lib64" &&
make -j $CPUS install-gcc &&
rm "$STAGE_DIR/lib64" &&

# Move the gcc internal libraries and headers somewhere sane

mkdir -p "$STAGE_DIR"/cc &&
mv "$STAGE_DIR"/lib/gcc/*/*/include "$STAGE_DIR"/cc/include &&
mv "$STAGE_DIR"/lib/gcc/*/* "$STAGE_DIR"/cc/lib &&

# Move the compiler internal binaries into "tools"
ln -s "$CROSS_TARGET" "$STAGE_DIR/tools" &&
cp "$STAGE_DIR/libexec/gcc/"*/*/c* "$STAGE_DIR/tools/bin" &&
rm -rf "$STAGE_DIR/libexec" || dienow

# collect2 is evil, kill it.
# ln -sf ../../../../tools/bin/ld  ${STAGE_DIR}/libexec/gcc/*/*/collect2 || dienow

if [ ! -z "$FROM_ARCH" ]
then
  # We also need to beat libsupc++ out of gcc (which uClibc++ needs to build).
  # But don't want to build the whole of libstdc++-v3 because
  # A) we're using uClibc++ instead,  B) the build breaks.

  # The libsupc++ ./configure dies if run after the simple cross compiling
  # ./configure, because gcc's build system is overcomplicated crap, so skip
  # the uClibc++ build first time around and only do it for the canadian cross
  # builds.  (The simple cross compiler still needs basic C++ support to build
  # the C++ libraries with, though.)

  make -j $CPUS configure-target-libstdc++-v3 &&
  cd "$CROSS_TARGET"/libstdc++-v3/libsupc++ &&
  make -j $CPUS &&
  mv .libs/libsupc++.a "$STAGE_DIR"/cc/lib || dienow
fi

# Prepare for ccwrap

mv "$STAGE_DIR/bin/${PROGRAM_PREFIX}"{gcc,rawcc} &&
ln -s "${PROGRAM_PREFIX}cc" "$STAGE_DIR/bin/${PROGRAM_PREFIX}gcc" &&

# Wrap C++ too.

mv "$STAGE_DIR/bin/${PROGRAM_PREFIX}"{g++,raw++} &&
rm -f "$STAGE_DIR/bin/${PROGRAM_PREFIX}c++" &&
ln -s "${PROGRAM_PREFIX}cc" "$STAGE_DIR/bin/${PROGRAM_PREFIX}g++" &&
ln -s "${PROGRAM_PREFIX}cc" "$STAGE_DIR/bin/${PROGRAM_PREFIX}c++" || dienow

# Make sure "tools" has everything distccd needs.

cd "$STAGE_DIR/tools" || dienow
ln -s ../../bin/${PROGRAM_PREFIX}rawcc "$STAGE_DIR/tools/bin/gcc" 2>/dev/null
ln -s ../../bin/${PROGRAM_PREFIX}rawcc "$STAGE_DIR/tools/bin/cc" 2>/dev/null
ln -s ../../bin/${PROGRAM_PREFIX}raw++ "$STAGE_DIR/tools/bin/g++" 2>/dev/null
ln -s ../../bin/${PROGRAM_PREFIX}raw++ "$STAGE_DIR/tools/bin/c++" 2>/dev/null

rm -rf build-gcc # "${STAGE_DIR}"/{lib/gcc,{libexec/gcc,gcc/lib}/install-tools,bin/${ARCH}-unknown-*}

mv "$WORK"/{gcc-core,gcc}
PACKAGE=gcc cleanup
