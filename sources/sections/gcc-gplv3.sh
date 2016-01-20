# These gcc components will be built automatically as submodules of gcc
setupfor gmp
setupfor mpfr
setupfor mpc
setupfor gcc gplv3

mv ${WORK}/gmp  ${WORK}/gcc
mv ${WORK}/mpfr ${WORK}/gcc
mv ${WORK}/mpc  ${WORK}/gcc

blank_workdir build-gcc

# The gcc ./configure manages to make the binutils one look sane.  Again,
# wrap it so we can call it with different variables to beat sense out of it.
function configure_gcc()
{
  # Explanation of configure flags used:
  #
  # --disable-libmudflap --disable-libsanitizer
  #
  #   These are used by the musl-cross-make project, just avoid trying to build
  #   those.
  #
  # --disable-lto
  #
  #   Disable the link time optimizer plugin, this wont build in the early phases
  #   and in the final phase it does not relocate well, gcc will enable usage
  #   of the plugin by default and then fail to load it with our ccwrap approach
  #   to gcc relocation (possibly fixable !)
  #

  # Configure gcc
  "$CURSRC/configure" --target="$CROSS_TARGET" --prefix="$STAGE_DIR" \
		      --program-prefix="$TOOLCHAIN_PREFIX" \
		      --disable-multilib --enable-tls \
		      --disable-libmudflap --disable-libsanitizer \
		      --disable-lto --disable-nls \
		      --disable-nls --enable-c99 --enable-__cxa_atexit \
		      --enable-long-long  \
    "$@" $GCC_FLAGS || dienow

  # Provide xgcc as a symlink to the target compiler, so gcc doesn't waste
  # time trying to rebuild itself with itself.  (If we want that, we'll do it
  # ourselves via canadian cross.)
  mkdir -p gcc &&
  ln -s "$(which ${CC_FOR_TARGET:-cc})" gcc/xgcc
}

# These are disabled while building the simpler cross
# compiler in both the BASE_GCC stage and the later
# host built cross compiler.
DISABLE_SHLIBS="--disable-libquadmath \
                --disable-libssp \
                --disable-libatomic \
                --disable-libgomp \
                --disable-libvtv "

if [ -z "$HOST_ARCH" ]
then

  # Building a cross compiler for the actual host, this is done in two passes, one
  # before a libc is present and then again afterwards to build C++ support.
  if [ ! -z "$BASE_GCC" ]
  then
    # Basic C compiler.
    #
    # The only prerequisite for this is binutils, above.  (It doesn't even
    # require a C library for the target to exist yet, which is good because you
    # have a chicken and egg problem otherwise.  What would you have compiled
    # that C library _with_?)
    AR_FOR_TARGET="${CC_PREFIX}ar" configure_gcc \
		 --build="$CROSS_HOST" --host="$CROSS_HOST" \
		 --disable-threads --disable-shared $DISABLE_SHLIBS \
		 --enable-languages=c

  else
    # Cross compiler to run on build host
    #
    # Basic compiler, we now have a libc compiled, we need to build a compiler
    # again with the host tooling, this time with access to compiled libc.
    #
    # This compiler needs to build full C++ support so that it can be used to
    # build the canadian cross compiler in the next step (gcc needs C++ to build).
    AR_FOR_TARGET="${CC_PREFIX}ar" configure_gcc \
		 --build="$CROSS_HOST" --host="$CROSS_HOST" \
		 --disable-threads --disable-shared $DISABLE_SHLIBS \
		 --enable-languages=c,c++
  fi

else
  # Canadian cross compiler (and cross compiled native compiler)
  #
  # Canadian cross a compiler to run on $HOST_ARCH as its host and output
  # binaries for $ARCH as its target.
  #
  # GCC has some deep assumptions here, which are wrong.  Lots of redundant
  # corrections are required to make it stop.
  [ -z "$ELF2FLT" ] && X=--enable-shared || X=--disable-shared
  CC="${HOST_ARCH}-cc" CXX="${HOST_ARCH}-c++" AR="${HOST_ARCH}-ar" AS="${HOST_ARCH}-as" \
    LD="${HOST_ARCH}-ld" NM="${HOST_ARCH}-nm" RANLIB="${HOST_ARCH}-ranlib" \
    CC_FOR_TARGET="${CC_PREFIX}cc" AR_FOR_TARGET="${CC_PREFIX}ar" \
    NM_FOR_TARGET="${CC_PREFIX}nm" GCC_FOR_TARGET="${CC_PREFIX}cc" \
    AS_FOR_TARGET="${CC_PREFIX}as" LD_FOR_TARGET="${CC_PREFIX}ld" \
    CXX_FOR_TARGET="${CC_PREFIX}c++" RANLIB_FOR_TARGET="${CC_PREFIX}ranlib" \
    ac_cv_path_AR_FOR_TARGET="${CC_PREFIX}ar" \
    ac_cv_path_CXX_FOR_TARGET="${CC_PREFIX}c++" \
    ac_cv_path_RANLIB_FOR_TARGET="${CC_PREFIX}ranlib" \
    ac_cv_path_NM_FOR_TARGET="${CC_PREFIX}nm" \
    ac_cv_path_AS_FOR_TARGET="${CC_PREFIX}as" \
    ac_cv_path_LD_FOR_TARGET="${CC_PREFIX}ld" \
    configure_gcc --enable-threads=posix $X \
      --build="$CROSS_HOST" --host="${CROSS_TARGET/unknown-elf/walrus-elf}" --enable-languages=c,c++
fi

# Now that it's configured, build and install gcc
make -j $CPUS LDFLAGS="$STATIC_FLAGS" || dienow

# Work around gcc bug during the install: we disabled multilib but it doesn't
# always notice.
ln -s lib "$STAGE_DIR/lib64" &&
make -j $CPUS install &&
rm "$STAGE_DIR/lib64" || dienow

# We leave the installation as is when compiling
# the base GCC, only bother to wrap up the fully
# built compilers for ccwrap.
if [ -z "$BASE_GCC" ]
then
  mkdir -p "$STAGE_DIR"/cc/lib &&
  mkdir -p "$STAGE_DIR"/c++ || dienow

  # Move the gcc internal libraries and headers somewhere sane
  rm -rf "$STAGE_DIR"/lib/gcc/*/*/install-tools 2>/dev/null
  mv "$STAGE_DIR"/lib/gcc/*/*/include "$STAGE_DIR"/cc/include &&
  mv "$STAGE_DIR"/lib/gcc/*/*/* "$STAGE_DIR"/cc/lib || dienow

  # When compiling where host == target, gcc doesnt prefix the installed
  # C++ headers with the target triple (as it's a native compiler)
  #
  # XXX This needs to make the correct if, check if host == target
  CXX_HEADERS_BASE="$STAGE_DIR/$CROSS_TARGET"
  if [ ! -z "$HOST_ARCH" ]
  then
    CXX_HEADERS_BASE="$STAGE_DIR"
  fi
  mv "$CXX_HEADERS_BASE"/include/c++/* "$STAGE_DIR"/c++/include &&
  ln -s "$CROSS_TARGET" "$STAGE_DIR"/c++/include/extra-includes &&

  # Move the compiler internal binaries into "tools"
  ln -s "$CROSS_TARGET" "$STAGE_DIR/tools" &&
  cp "$STAGE_DIR/libexec/gcc/"*/*/c* "$STAGE_DIR/tools/bin" &&
  rm -rf "$STAGE_DIR/libexec" || dienow

  # libgcc_eh.a is missing unless built with shared libs, which is only done for
  # the second pass in canadian cross. Work around this problem by just pretending
  # that libgcc.a has the exception handling which should be provided by libgcc_eh.a,
  # it's good enough for the purposes of the simple cross compiler at least
  if [ -z "$HOST_ARCH" ]
  then
    ln -s libgcc.a "$STAGE_DIR/cc/lib/libgcc_eh.a"
  fi

  # Prepare for ccwrap
  mv "$STAGE_DIR/bin/${TOOLCHAIN_PREFIX}gcc" "$STAGE_DIR/tools/bin/cc" &&
  ln -sf "${TOOLCHAIN_PREFIX}cc" "$STAGE_DIR/bin/${TOOLCHAIN_PREFIX}gcc" &&
  ln -s cc "$STAGE_DIR/tools/bin/rawcc" &&

  # Wrap C++ too.
  mv "$STAGE_DIR/bin/${TOOLCHAIN_PREFIX}g++" "$STAGE_DIR/tools/bin/c++" &&
  ln -sf "${TOOLCHAIN_PREFIX}cc" "$STAGE_DIR/bin/${TOOLCHAIN_PREFIX}g++" &&
  ln -sf "${TOOLCHAIN_PREFIX}cc" "$STAGE_DIR/bin/${TOOLCHAIN_PREFIX}c++" &&
  ln -s c++ "$STAGE_DIR/tools/bin/raw++" || dienow

  # Make sure "tools" has everything distccd needs.
  cd "$STAGE_DIR/tools" || dienow
  ln -s cc "$STAGE_DIR/tools/bin/gcc" 2>/dev/null
  ln -s c++ "$STAGE_DIR/tools/bin/g++" 2>/dev/null

  rm -rf "${STAGE_DIR}"/{lib/gcc,libexec/gcc/install-tools,bin/${ARCH}-unknown-*}
fi

cleanup
