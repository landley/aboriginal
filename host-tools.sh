#!/bin/bash

# Get lots of predefined environment variables and shell functions.

# Tell bash not to cache the $PATH to anything, so busybox/toybox utilities
# get used immediately even if a different executable was found last lookup.
set +h

NO_ARCH=1
source sources/include.sh

echo -e "$HOST_COLOR"
echo "=== Building host tools"

export LC_ALL=C

mkdir -p "${HOSTTOOLS}" || dienow

# If we want to record the host command lines, so we know exactly what commands
# the build uses.

if [ ! -z "$RECORD_COMMANDS" ]
then
  if [ ! -f "$BUILD/wrapdir/wrappy" ]
  then
    echo setup wrapdir

    # Build the wrapper and install it into build/wrapdir/wrappy
    rm -rf "$BUILD/wrapdir"
    mkdir "$BUILD/wrapdir" &&
    $CC -Os "$SOURCES/toys/wrappy.c" -o "$BUILD/wrapdir/wrappy"  || dienow

    # Loop through each $PATH element and create a symlink to the wrapper with
    # that name.

    for i in $(echo $PATH | sed 's/:/ /g')
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
# into mini-native.  When we're done, PATH can be set to include just this
# directory and nothing else.

# This serves three purposes:
#
# 1) Enumerate exactly what we need to build the system, so we can make sure
#    mini-native has everything it needs to rebuild us.  If anything is missing
#    from this list, the resulting mini-native probably won't have it either,
#    so it's nice to know as early as possible that we actually needed it.
#
# 2) Quick smoke test that the versions of the tools we're using can compile
#    everything from source correctly, and thus mini-native should be able to
#    rebuild from source using those same tools.
#
# 3) Reduce variation from distro to distro.  The build always uses the
#    same command line utilities no matter where we're running, because we
#    provide our own.

else

  # Start by creating symlinks to the host toolchain, since we need to use
  # that to build anything else.  We build a cross compiler, and a native
  # compiler for the target, but we don't build a host toolchain.  We use the
  # one that's already there.

  for i in ar as nm cc gcc make ld
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
fi

# This is optionally used by mini-native to accelerate native builds when
# running under qemu.  It's not used to build mini-native, or to build
# the cross compiler, but it needs to be on the host system in order to
# use the distcc acceleration trick.

# Note that this one we can use off of the host, it's used on the host where
# the system image runs.  The build doesn't actually use it, we only bother
# to build it at all here as a convenience for run-from-build.sh.

# Build distcc (if it's not in $PATH)
if [ -z "$(which distccd)" ]
then
echo build distcc
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

# Squashfs is an alternate packaging option.

#if [ ! -f "${HOSTTOOLS}"/mksquashfs ]
#then
#  setupfor squashfs &&
#  cd squashfs-tools &&
#  make &&
#  cp mksquashfs unsquashfs "${HOSTTOOLS}" &&
#  cd ..
#
#  cleanup squashfs
#fi

if [ ! -z "$RECORD_COMMANDS" ]
then 
  # Make sure the host tools we just built are also in wrapdir
  for j in $(ls "$HOSTTOOLS")
  do
    [ -e "$BUILD/wrapdir/$j" ] || ln -s wrappy "$BUILD/wrapdir/$j"
  done
fi

echo -e "\e[32mHost tools build complete.\e[0m"
