#!/bin/bash

# This script sets up a known host environment.  It serves a similar purpose
# to the temporary chroot system in Linux From Scratch chapter 5, isolating
# the new build from the host system so information from the host doesn't
# accidentally leak into the target.

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

echo -e "$HOST_COLOR"
echo "=== Building $STAGE_NAME"

export LC_ALL=C

STAGE_DIR="${HOSTTOOLS}"

# Blank $WORK but accept $STAGE_DIR if it exists.  Re-running this script
# should be a NOP.

blank_tempdir "${WORK}"
mkdir -p "${STAGE_DIR}" || dienow

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

  # Use the new tools we build preferentially, as soon as they become
  # available.

  PATH="$STAGE_DIR:$PATH"

  # Start by building busybox.  We have no idea what strange things our host
  # system has (or lacks, such as "which"), so throw busybox at it first
  # thing.

  if [ ! -f "${STAGE_DIR}/busybox" ]
  then
    build_section busybox
  fi

  # Create symlinks to the host toolchain.  We need a usable existing host
  # toolchain in order to build anything else (even a new host toolchain),
  # and we don't really want to have to care what the host type is, so
  # just use the toolchain that's already there.

  # This is a little more complicated than it needs to be, because the host
  # toolchain may be using ccache and/or distcc, which means we need every
  # instance of these tools that occurs in the $PATH, in order, each in its
  # own fallback directory.

  for i in ar as nm cc make ld gcc
  do
    if [ ! -f "${STAGE_DIR}/$i" ]
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
    fi
  done

  # We now have all the tools we need in $STAGE_DIR, so trim the $PATH to
  # remove the old ones.

  PATH="$(hosttools_path)"
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

# Busybox used to provide ext2 utilities (back around 1.2.2), but the
# implementation was horrible and got removed.  Someday the new Lua
# toybox should provide these.

# This mostly isn't used creating a system image, which uses genext2fs instead.
# If SYSIMAGE_HDA_MEGS is > 64, it'll resize2fs because genext2fs is
# unreasonably slow at creating large files.

# The hdb.img of run-emulator.sh and run-from-build.sh uses e2fsprogs'
# fsck.ext2 and tune2fs.  These are installed by default in most distros
# (which genext2fs isn't), and genext2fs doesn't have ext3 support anyway.

if [ ! -f "${STAGE_DIR}"/mke2fs ]
then
  setupfor e2fsprogs &&
  ./configure --disable-tls --enable-htree &&
  make -j "$CPUS" &&
  cp misc/{mke2fs,tune2fs} resize/resize2fs "${STAGE_DIR}" &&
  cp e2fsck/e2fsck "$STAGE_DIR"/fsck.ext2

  cleanup
fi

# Squashfs is an alternate packaging option.

if [ ! -f "${STAGE_DIR}"/mksquashfs ]
then
  setupfor squashfs &&
  cd squashfs-tools &&
  make -j $CPUS &&
  cp mksquashfs unsquashfs "${STAGE_DIR}"

  cleanup
fi

# Here's some stuff that isn't used to build a cross compiler or system
# image, but is used by run-from-build.sh.  By default we assume it's
# installed on the host you're running system images on (which may not be
# the one you're building them on).

# Either build qemu from source, or symlink it.

if [ ! -f "${STAGE_DIR}"/qemu ]
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
    ./configure --disable-gfx-check --prefix="$STAGE_DIR" &&
    make -j $CPUS &&
    # Copy the executable files and ROM files
    cp $(find -type f -perm +111 -name "qemu*") "$STAGE_DIR" &&
    cp -r pc-bios "$STAGE_DIR"

    cleanup
  else
    # Symlink qemu out of the host, if found.  Since run-from-build.sh uses
    # $PATH=.../build/host if it exists, add the various qemu instances to that.

    echo "$OLDPATH" | sed 's/:/\n/g' | while read i
    do
      for j in $(cd "$i"; ls qemu* 2>/dev/null)
      do
        ln -s "$i/$j" "$STAGE_DIR/$j"
      done
    done
  fi
fi

if [ ! -z "$RECORD_COMMANDS" ]
then 
  # Make sure the host tools we just built are also in wrapdir
  for j in $(ls "$STAGE_DIR")
  do
    [ -e "$BUILD/wrapdir/$j" ] || ln -s wrappy "$BUILD/wrapdir/$j"
  done
fi

echo -e "\e[32mHost tools build complete.\e[0m"
