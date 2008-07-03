#!/bin/bash

# Get lots of predefined environment variables and shell functions.

# Tell bash not to memorize the path to anything, so toybox utilities get
# used immediately even if a different executable was found last $PATH lookup.
set +h

echo -e "\e[0m"
echo "=== Building host tools"

NO_ARCH=1
source include.sh

mkdir -p "${HOSTTOOLS}" || dienow

# If we want to record the host command lines, so we know exactly what commands
# the build uses.

if [ ! -z "$RECORD_COMMANDS" ]
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
      ln -s wrappy "$BUILD/wrapdir/$j"
    done
  done

  # Adjust things to use wrapper directory

  export WRAPPY_REALPATH="$PATH"
  PATH="$BUILD/wrapdir"

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
    [ ! -f "${HOSTTOOLS}/$i" ] && (ln -s `which $i` "${HOSTTOOLS}/$i" || dienow)
  done

  # These commands need to be added to toybox.  The build breaks if we use
  # the busybox-1.2.2 versions, where available.  I'm working to remove this
  # hunk...

  for i in bzip2 find install od diff wget
  do
    [ ! -f "${HOSTTOOLS}/$i" ] && (ln -s `which $i` "${HOSTTOOLS}/$i" || dienow)
  done

  # Build toybox

  if [ ! -f "${HOSTTOOLS}/toybox" ]
  then
    setupfor toybox &&
    make defconfig &&
    make install_flat PREFIX="${HOSTTOOLS}" &&
    cd ..

    cleanup toybox
  fi

  # Build busybox

  # Yes this is an old version of busybox.  (It's the last version I released
  # as busybox maintainer.)  We're gradually replacing busybox with toybox, one
  # command at a time.

  if [ ! -f "${HOSTTOOLS}/busybox" ]
  then
    setupfor busybox &&
    cp "${SOURCES}/config-busybox" .config &&
    yes "" | make oldconfig &&
    make &&
    cp busybox "${HOSTTOOLS}"

    [ $? -ne 0 ] && dienow

    for i in $(sed 's@.*/@@' busybox.links)
    do
      ln -s busybox "${HOSTTOOLS}"/$i || dienow
    done
    cd ..

    cleanup busybox
  fi
fi


# This is optionally used by mini-native to accelerate native builds when
# running under qemu.  It's not used to build mini-native, or to build
# the cross compiler, but it needs to be on the host system in order to
# use the distcc acceleration trick.

# Build distcc (if it's not in $PATH)
if [ -z "$(which distcc)" ]
then
  setupfor distcc &&
  ./configure --with-included-popt &&
  make -j "$CPUS" &&
  cp distcc distccd "${HOSTTOOLS}" &&
  cd ..

  cleanup distcc
fi

# As a temporary measure, build User Mode Linux and use _that_ to package
# the ext2 image to boot qemu with.  (Replace this with toybox gene2fs.)

if [ ! -f "${HOSTTOOLS}/linux" ]
then
  setupfor linux &&
  cat > mini.conf << EOF &&
CONFIG_BINFMT_ELF=y
CONFIG_HOSTFS=y
CONFIG_LBD=y
CONFIG_BLK_DEV=y
CONFIG_BLK_DEV_LOOP=y
CONFIG_STDERR_CONSOLE=y
CONFIG_UNIX98_PTYS=y
CONFIG_EXT2_FS=y
EOF
  make ARCH=um allnoconfig KCONFIG_ALLCONFIG=mini.conf &&
  make -j "$CPUS" ARCH=um &&
  cp linux "${HOSTTOOLS}" &&
  cd ..

  cleanup linux
fi

# Everything after here is stuff we _could_ build, but currently don't.

# Build squashfs
#setupfor squashfs
#cd squashfs-tools &&
#make &&
#cp mksquashfs unsquashfs "${HOSTTOOLS}" &&
#cd ..
#
#cleanup squashfs

if [ ! -z "$RECORD_COMMANDS" ]
then 
  # Add the host tools we just built to wrapdir
  for j in $(ls "$HOSTTOOLS")
  do
    ln -s wrappy "$BUILD/wrapdir/$j"
  done
fi

echo -e "\e[32mHost tools build complete.\e[0m"
