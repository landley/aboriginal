# Build busybox statically by default, but don't statically link against
# glibc because glibc is buggy and can't combine --static with --gc-sections.

[ "$BUILD_STATIC" != "none" ] && [ ! -z "$ARCH" ] && BUSYBOX_STATIC="--static"
[ ! -z "$ARCH" ] && DO_CROSS=CROSS_COMPILE=${ARCH}-

# Build busybox

setupfor busybox
make allyesconfig KCONFIG_ALLCONFIG="${SOURCES}/trimconfig-busybox" &&
cp .config "$WORK"/config-busybox &&
LDFLAGS="$LDFLAGS $BUSYBOX_STATIC" make -j $CPUS $VERBOSITY $DO_CROSS &&
make busybox.links &&
cp busybox${SKIP_STRIP:+_unstripped} "${STAGE_DIR}/busybox" || dienow

for i in $(sed 's@.*/@@' busybox.links)
do
  [ ! -f "${STAGE_DIR}/$i" ] &&
    (ln -sf busybox "${STAGE_DIR}/$i" || dienow)
done

cleanup
