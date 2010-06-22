#!/bin/bash

# Set up a known host environment, providing known versions of all required
# prerequisites, built from source.

# This script serves a similar purpose to the temporary chroot system in
# Linux From Scratch chapter 5, isolating the new build from the host system
# so information from the host doesn't accidentally leak into the target.

# This script populates a build/host directory with busybox and symlinks to
# the host's toolchain, then adds the other packages (genext2fs, e2fsprogs,
# squashfs-tools, distcc, and qemu) that might be needed to package and run
# a system image.  This lets the rest of the build run with the $PATH pointing
# at the new build/host directory and nothing else.

# The tools provided by this stage are as similar as possible to the ones
# provided in the final system image.  The fact the system can build under
# these tools is a good indication that it should be able to rebuild itself
# under itself.

# This script is optional.  The build runs fine without it, assuming the
# host has all the necessary packages installed and doesn't have any extra
# packages (such as libtool, pkg-config, python...) that might provide
# false information to autoconf or attach themselves as dependencies to
# the newly generated programs.  (In practice, this can be quite fiddly.)

source sources/include.sh || exit 1

echo "=== Building $STAGE_NAME"

STAGE_DIR="${HOSTTOOLS}"

# Blank $WORK but accept $STAGE_DIR if it exists.  Re-running this script
# should be a NOP.

blank_tempdir "$WORK"
mkdir -p "$STAGE_DIR" || dienow

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

# Use the new tools we build preferentially, as soon as they become
# available.

PATH="$STAGE_DIR:$PATH"

# Sanity test for the host supporting static linking.

if [ "$BUILD_STATIC" != none ]
then
  $CC "$SOURCES/toys/hello.c" --static -o "$STAGE_DIR/hello-$$" &&
  rm "$STAGE_DIR/hello-$$"

  if [ $? -ne 0 ]
  then
    echo "Your host toolchain does not support static linking." >&2
    echo "Either install support, or export BUILD_STATIC=none" >&2

    dienow
  fi
fi


# Start by building busybox.  We have no idea what strange things our host
# system has (or lacks, such as "which"), so throw busybox at it first
# thing.

[ ! -f "$STAGE_DIR/busybox" ] && build_section busybox
[ ! -f "$STAGE_DIR/toybox" ] && build_section toybox

# Create symlinks to the host toolchain.  We need a usable existing host
# toolchain in order to build anything else (even a new host toolchain),
# and we don't really want to have to care what the host type is, so
# just use the toolchain that's already there.

# This is a little more complicated than it needs to be, because the host
# toolchain may be using ccache and/or distcc, which means we need every
# instance of these tools that occurs in the $PATH, in order, each in its
# own fallback directory.

for i in ar as nm cc make ld gcc $HOST_EXTRA
do
  if [ ! -f "$STAGE_DIR/$i" ]
  then
    # Loop through each instance, populating fallback directories.

    X=0
    FALLBACK="$STAGE_DIR"
    PATH="$OLDPATH" "$STAGE_DIR/which" -a "$i" | while read j
    do
      mkdir -p "$FALLBACK" &&
      ln -sf "$j" "$FALLBACK/$i" || dienow

      X=$[$X+1]
      FALLBACK="$STAGE_DIR/fallback-$X"
    done

    if [ ! -f "$STAGE_DIR/$i" ]
    then
      echo "Toolchain component missing: $i" >&2
      dienow
    fi
  fi
done

# Workaround for a bug in Ubuntu 10.04 where gcc became a perl script calling
# gcc.real.  Systems that aren't crazy don't need this.

ET_TU_UBUNTU="$(PATH="$OLDPATH" "$STAGE_DIR/which" gcc.real)"
[ ! -z "$ET_TU_UBUNTU" ] && ln -sf "$ET_TU_UBUNTU" "$STAGE_DIR/gcc.real"

# We now have all the tools we need in $STAGE_DIR, so trim the $PATH to
# remove the old ones.

PATH="$(hosttools_path)"

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
  cp distcc distccd "${STAGE_DIR}"

  cleanup
fi

# Build genext2fs.  We use it to build the ext2 image to boot qemu with
# in system-image.sh.

if [ ! -f "${STAGE_DIR}"/genext2fs ]
then
  setupfor genext2fs &&
  ./configure &&
  make -j $CPUS &&
  cp genext2fs "${STAGE_DIR}"

  cleanup
fi

# Build e2fsprogs.

# The hdb.img of run-emulator.sh and run-from-build.sh uses e2fsprogs'
# fsck.ext2 and tune2fs.  These are installed by default in most distros
# (which genext2fs isn't), and genext2fs doesn't have ext3 support anyway.

# system-image.sh will also use resize2fs from this package if
# SYSIMAGE_TYPE=ext2 to expand the image to SYSIMAGE_HDA_MEGS, because
# genext2fs is unreasonably slow at creating large files.  (It has a -b
# option that should do this... if you want your 8-way server with 32 gigs
# of ram to sit there and drool for over 10 minutes to create a 2 gig file
# that's mostly empty.  Yeah: not doing that.)

if [ ! -f "${STAGE_DIR}"/mke2fs ]
then
  setupfor e2fsprogs &&
  ./configure --disable-tls --disable-nls --enable-htree &&
  make -j "$CPUS" &&
  cp misc/{mke2fs,tune2fs} resize/resize2fs "${STAGE_DIR}" &&
  cp e2fsck/e2fsck "$STAGE_DIR"/fsck.ext2

  cleanup
fi

# Squashfs is an alternate packaging option.

if [ ! -f "${STAGE_DIR}"/mksquashfs ] &&
  ([ -z "$SYSIMAGE_TYPE" ] || [ "$SYSIMAGE_TYPE" == squashfs ])
then
  setupfor zlib &&
  ./configure &&
  make -j $CPUS &&
  mv z*.h libz.a ..

  cleanup

  setupfor squashfs &&
  cd squashfs-tools &&
  CC="$CC -I ../.. -L ../.." make -j $CPUS  &&
  cp mksquashfs unsquashfs "${STAGE_DIR}" &&
  rm ../../{z*.h,libz.a}

  cleanup
fi

echo -e "\e[32mHost tools build complete.\e[0m"
