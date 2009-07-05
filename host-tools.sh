#!/bin/bash

# Get lots of predefined environment variables and shell functions.

source sources/include.sh || exit 1

echo -e "$HOST_COLOR"
echo "=== Building $STAGE_NAME"

export LC_ALL=C

blank_tempdir "${WORK}"
mkdir -p "${HOSTTOOLS}" || dienow

# If we want to record the host command lines, so we know exactly what commands
# the build uses, set up a wrapper that does that.

if [ ! -z "$RECORD_COMMANDS" ]
then
  if [ ! -f "$BUILD/wrapdir/wrappy" ]
  then
    echo setup wrapdir

    # Build the wrapper and install it into build/wrapdir/wrappy
    blank_tempdir "$BUILD/wrapdir"
    $CC -Os "$SOURCES/toys/wrappy.c" -o "$BUILD/wrapdir/wrappy"  || dienow

    # Loop through each $PATH element and create a symlink to the wrapper with
    # that name.

    for i in $(echo "$PATH" | sed 's/:/ /g')
    do
      for j in $(ls $i)
      do
        [ -f "$BUILD/wrapdir/$j" ] || ln -s wrappy "$BUILD/wrapdir/$j"
      done
    done

    # Adjust things to use wrapper directory

    export WRAPPY_REALPATH="$PATH"
    PATH="$BUILD/wrapdir"
  fi

# If we're not recording the host command lines, then populate a directory
# with host versions of all the command line utilities we're going to install
# into root-filesystem.  When we're done, PATH can be set to include just this
# directory and nothing else.

# This serves three purposes:
#
# 1) Enumerate exactly what we need to build the system, so we can make sure
#    root-filesystem has everything it needs to rebuild us.  If anything is
#    missing from this list, the resulting root-filesystem probably won't have
#    it either, so it's nice to know as early as possible that we actually
#    needed it.
#
# 2) Quick smoke test that the versions of the tools we're using can compile
#    everything from source correctly, and thus root-filesystem should be able
#    to rebuild from source using those same tools.
#
# 3) Reduce variation from distro to distro.  The build always uses the
#    same command line utilities no matter where we're running, because we
#    provide our own.

else

  # Start by creating symlinks to the host toolchain, since we need to use
  # that to build anything else.  We build a cross compiler, and a native
  # compiler for the target, but we don't build a host toolchain.  We use the
  # one that's already there.

  for i in ar as nm cc make ld gcc
  do
    [ ! -f "${HOSTTOOLS}/$i" ] &&
      (ln -s `PATH="$OLDPATH" which $i` "${HOSTTOOLS}/$i" || dienow)
  done

  # Build toybox

  if [ ! -f "${HOSTTOOLS}/toybox" ]
  then
    setupfor toybox &&
    make defconfig &&
    make || dienow
    if [ -z "$USE_TOYBOX" ]
    then
      mv toybox "$HOSTTOOLS" &&
      ln -s toybox "$HOSTTOOLS"/patch &&
      ln -s toybox "$HOSTTOOLS"/netcat || dienow
    else
      make install_flat PREFIX="${HOSTTOOLS}" || dienow
    fi
    cd ..

    cleanup toybox
  fi

  # Build busybox

  if [ ! -f "${HOSTTOOLS}/busybox" ]
  then
    setupfor busybox &&
    make allyesconfig KCONFIG_ALLCONFIG="${SOURCES}/trimconfig-busybox" &&
    make -j $CPUS &&
    make busybox.links &&
    cp busybox "${HOSTTOOLS}"

    [ $? -ne 0 ] && dienow

    for i in $(sed 's@.*/@@' busybox.links)
    do
      [ ! -f "${HOSTTOOLS}/$i" ] &&
        (ln -s busybox "${HOSTTOOLS}/$i" || dienow)
    done
    cd ..

    cleanup busybox
  fi

  PATH="${HOSTTOOLS}"
fi

# This is optionally used by root-filesystem to accelerate native builds when
# running under qemu.  It's not used to build root-filesystem, or to build
# the cross compiler, but it needs to be on the host system in order to
# use the distcc acceleration trick.

# Note that this one we can use off of the host, it's used on the host where
# the system image runs.  The build doesn't actually use it, we only bother
# to build it at all here as a convenience for run-from-build.sh.

# Build distcc (if it's not in $PATH)
if [ -z "$(which distccd)" ]
then
  setupfor distcc &&
  ./configure --with-included-popt --disable-Werror &&
  make -j "$CPUS" &&
  cp distcc distccd "${HOSTTOOLS}" &&
  cd ..

  cleanup distcc
fi

# Build genext2fs.  We use it to build the ext2 image to boot qemu with
# in system-image.sh.

if [ ! -f "${HOSTTOOLS}"/genext2fs ]
then
  setupfor genext2fs &&
  ./configure &&
  make -j $CPUS &&
  cp genext2fs "${HOSTTOOLS}" &&
  cd ..

  cleanup genext2fs
fi

# Build e2fsprogs.

# Busybox used to provide ext2 utilities (back around 1.2.2), but the
# implementation was horrible and got removed.  Someday the new Lua
# toybox should provide these.

# This mostly isn't used creating a system image, which uses genext2fs instead.
# If SYSIMAGE_HDA_MEGS is > 64, it'll resize2fs because genext2fs is
# unreasonably slow at creating large files.

# The hdb.img of run-emulator.sh and run-from-build.sh uses e2fsprogs'
# fsck.ext2 and tune2fs.  These are installed by default in most distros
# (which genext2fs isn't), and genext2fs doesn't have ext3 support anyway.

if [ ! -f "${HOSTTOOLS}"/mke2fs ]
then
  setupfor e2fsprogs &&
  ./configure --disable-tls --enable-htree &&
  make -j "$CPUS" &&
  cp misc/{mke2fs,tune2fs} resize/resize2fs "${HOSTTOOLS}" &&
  cp e2fsck/e2fsck "$HOSTTOOLS"/fsck.ext2 &&
  cd ..

  cleanup e2fsprogs
fi

# Squashfs is an alternate packaging option.

if [ ! -f "${HOSTTOOLS}"/mksquashfs ]
then
  setupfor squashfs &&
  cd squashfs-tools &&
  make -j $CPUS &&
  cp mksquashfs unsquashfs "${HOSTTOOLS}" &&
  cd ..

  cleanup squashfs
fi

# Here's some stuff that isn't used to build a cross compiler or system
# image, but is used by run-from-build.sh.  By default we assume it's
# installed on the host you're running system images on (which may not be
# the one you're building them on).

# Either build qemu from source, or symlink it.

if [ ! -f "${HOSTTOOLS}"/qemu ]
then
  if [ ! -z "$HOST_BUILD_EXTRA" ]
  then

    # Build qemu.  Note that this is _very_slow_.  (It takes about as long as
    # building a system image from scratch, including the cross compiler.)

    # It's also ugly: its wants to populate a bunch of subdirectories under
    # --prefix, and we can't just install it in host-temp and copy out what
    # we want because the pc-bios directory needs to exist at a hardwired
    # absolute path, so we do the install by hand.

    setupfor qemu &&
    cp "$SOURCES"/patches/openbios-ppc pc-bios/openbios-ppc &&
    sed -i 's@datasuffix=".*"@datasuffix="/pc-bios"@' configure &&
    ./configure --disable-gfx-check --prefix="$HOSTTOOLS" &&
    make -j $CPUS &&
    # Copy the executable files and ROM files
    cp $(find -type f -perm +111 -name "qemu*") "$HOSTTOOLS" &&
    cp -r pc-bios "$HOSTTOOLS" &&
    cd ..

    cleanup qemu
  else
    # Symlink qemu out of the host, if found.  Since run-from-build.sh uses
    # $PATH=.../build/host if it exists, add the various qemu instances to that.

    echo "$OLDPATH" | sed 's/:/\n/g' | while read i
    do
      for j in $(cd "$i"; ls qemu* 2>/dev/null)
      do
        ln -s "$i/$j" "$HOSTTOOLS/$j"
      done
    done
  fi
fi

if [ ! -z "$RECORD_COMMANDS" ]
then 
  # Make sure the host tools we just built are also in wrapdir
  for j in $(ls "$HOSTTOOLS")
  do
    [ -e "$BUILD/wrapdir/$j" ] || ln -s wrappy "$BUILD/wrapdir/$j"
  done
fi

echo -e "\e[32mHost tools build complete.\e[0m"
