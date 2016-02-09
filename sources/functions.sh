#!/bin/echo "This file is sourced, not run"

# Lots of reusable functions.  This file is sourced, not run.

# Output path to cross compiler.

cc_path()
{
  local i

  if [ ! -z "$MY_CROSS_PATH" ]
  then
    CC_PREFIX="$MY_CC_PREFIX"
    [ -z "$CC_PREFIX" ] &&
      echo "MY_CROSS_PATH without MY_CC_PREFIX" >&2 &&
      dienow
    echo -n "$MY_CROSS_PATH:"
    return
  fi

  # Output cross it if exists, else simple.  If neither exists, output simple.

  for i in "$BUILD"/{,simple-}cross-compiler-"$1/bin"
  do
    [ -e "$i/$1-cc" ] && break
  done
  echo -n "$i:"
}

base_architecture()
{
  ARCH="$1"
  source "$CONFIG_DIR/$1"
}

load_target()
{
  # Get target platform from first command line argument.

  ARCH_NAME="$1"
  CONFIG_DIR="$SOURCES/targets"

  # Read the relevant config file.

  if [ -f "$CONFIG_DIR/$1" ]
  then
    base_architecture "$ARCH_NAME"
    CONFIG_DIR=
  elif [ -f "$CONFIG_DIR/$1/settings" ]
  then
    source "$CONFIG_DIR/$1/settings"
    [ -z "$ARCH" ] && dienow "No base_architecture"
  else
    echo "Supported architectures: "
    ls "$CONFIG_DIR"

    exit 1
  fi

  # Which platform are we building for?

  export WORK="${BUILD}/temp-$ARCH_NAME"

  # Say "unknown" in two different ways so it doesn't assume we're NOT
  # cross compiling when the host and target are the same processor.  (If host
  # and target match, the binutils/gcc/make builds won't use the cross compiler
  # during root-filesystem.sh, and the host compiler links binaries against the
  # wrong libc.)
  export_if_blank CROSS_HOST=`uname -m`-walrus-linux
  export_if_blank CROSS_TARGET=${ARCH}-unknown-linux

  # Setup directories and add the cross compiler to the start of the path.

  STAGE_DIR="$BUILD/${STAGE_NAME}-${ARCH_NAME}"

  if [ -z "$KEEP_STAGEDIR" ]
  then
    blank_tempdir "$STAGE_DIR"
  else
    mkdir -p "$STAGE_DIR" || dienow
  fi
  NO_CLEANUP=${NO_CLEANUP/temp//} blank_tempdir "$WORK"

  export PATH="$(cc_path "$ARCH")$PATH"
  [ ! -z "$HOST_ARCH" ] && [ "$HOST_ARCH" != "$ARCH" ] &&
    PATH="$(cc_path "$HOST_ARCH")$PATH"

  export_if_blank CC_PREFIX="${ARCH}-"
  DO_CROSS="CROSS_COMPILE=$CC_PREFIX"

  return 0
}

# Note that this sources the file, rather than calling it as a separate
# process.  That way it can set environment variables if it wants to.
#
# If $2 is given, it is used as a variant name for the build script
# and patches instead of $1, $2 is essentially a variant of the
# package $1 and allows basic support for multiple versions of the
# same package.
build_section()
{
  PACKAGE_NAME=$1
  SCRIPT_NAME=$1
  PACKAGE_VARIANT=
  if [ ! -z "$2" ]
  then
    PACKAGE_VARIANT="$2"
    SCRIPT_NAME="${PACKAGE_NAME}-${PACKAGE_VARIANT}"
  fi

  # Don't build anything statically in host-tools, glibc is broken.
  # See http://people.redhat.com/drepper/no_static_linking.html for
  # insane rant from the glibc maintainer about why he doesn't care.
  is_in_list $PACKAGE_NAME $BUILD_STATIC && [ ! -z "$ARCH" ] && STATIC_FLAGS="--static"

  OLDCPUS=$CPUS
  OLDNOCLEAN=$NO_CLEANUP
  is_in_list $PACKAGE_NAME $DEBUG_PACKAGE && CPUS=1 && NO_CLEANUP=1

  if [ -e "$SOURCES/sections/$SCRIPT_NAME".build ]
  then
    setupfor "$PACKAGE_NAME" "$PACKAGE_VARIANT"
    . "$SOURCES/sections/$SCRIPT_NAME".build
    cleanup
  else
    announce "$PACKAGE_NAME"
    . "$SOURCES"/sections/"$SCRIPT_NAME".sh
  fi
  CPUS=$OLDCPUS
  NO_CLEANUP=$OLDNOCLEAN
}

# Find appropriate miniconfig file

getconfig()
{
  for i in {$ARCH_NAME,$ARCH}/miniconfig-$1
  do
    [ -f "$CONFIG_DIR/$i" ] && cat "$CONFIG_DIR/$i" && return
  done

  # Output baseconfig, then append $1_CONFIG (converting $1 to uppercase)
  cat "$SOURCES/baseconfig-$1"
  eval "echo \"\${$(echo $1 | tr a-z A-Z)_CONFIG}\""
}

# Find all files in $STAGE_DIR newer than $CURSRC.

recent_binary_files()
{
  PREVIOUS=
  (cd "$STAGE_DIR" || dienow
   find . -depth -newer "$CURSRC/BUILD-TIMESTAMP" \
     | sed -e 's/^.//' -e 's/^.//' -e '/^$/d'
  ) | while read i
  do
    TEMP="${PREVIOUS##"$i"/}"

    if [ $[${#PREVIOUS}-${#TEMP}] -ne $[${#i}+1] ]
    then
      # Because the expanded $i might have \ chars in it, that's why.
      echo -n "$i"
      echo -ne '\0'
    fi
    PREVIOUS="$i"
  done
}

# Delete a working copy of source code once the build's done.

cleanup()
{
  # If package build exited with an error, do not continue.

  [ $? -ne 0 ] && dienow

  if [ ! -z "$BINARY_PACKAGE_TARBALLS" ]
  then
    TARNAME="$PACKAGE-$STAGE_NAME-${ARCH_NAME}".tar.gz
    [ ! -z "$(recent_binary_files)" ] &&
      echo -n Creating "$TARNAME" &&
      { recent_binary_files | xargs -0 tar -czvf \
          "$BUILD/${TARNAME}" -C "$STAGE_DIR" || dienow
      } | dotprogress
  fi

  if [ ! -z "$NO_CLEANUP" ]
  then
    echo "skip cleanup $PACKAGE $@"
    return
  fi

  # Loop deleting directories

  cd "$WORK" || dienow
  for i in $WORKDIR_LIST
  do
    echo "cleanup $i"
    rm -rf "$i" || dienow
  done
  WORKDIR_LIST=
}

# Create a working directory under TMPDIR, deleting existing contents (if any),
# and tracking created directories so cleanup can delete them automatically.

blank_workdir()
{
  WORKDIR_LIST="$1 $WORKDIR_LIST"
  NO_CLEANUP= blank_tempdir "$WORK/$1"
  cd "$WORK/$1" || dienow
}

# Extract package $1
#
# If $2 is specified it is a variant of the package, as such
# the variant name will be used as a basename for the patches instead
# of $1
setupfor()
{
  export WRAPPY_LOGPATH="$BUILD/logs/cmdlines.${ARCH_NAME}.${STAGE_NAME}.setupfor"

  # Make sure the source is already extracted and up-to-date.
  extract_package "$1" "$2" || exit 1
  SNAPFROM="$(package_cache "$1")"

  # Delete old working copy (even in the NO_CLEANUP case) then make a new
  # tree of links to the package cache.

  echo "Snapshot '$PACKAGE'..."

  # Try hardlink, then symlink, then normal (noclobber) copy
  for LINKTYPE in l s n
  do
    if [ -z "$REUSE_CURSRC" ]
    then
      blank_workdir "$PACKAGE"
      CURSRC="$(pwd)"
    fi

    cp -${LINKTYPE}fR "$SNAPFROM/"* "$CURSRC" && break
  done

  cd "$CURSRC" || dienow
  export WRAPPY_LOGPATH="$BUILD/logs/cmdlines.${ARCH_NAME}.${STAGE_NAME}.$1"

  # Ugly bug workaround: timestamp granularity in a lot of filesystems is only
  # 1 second, so find -newer misses things installed in the same second, so we
  # make sure it's a new second before we start actually doing anything.

  if [ ! -z "$BINARY_PACKAGE_TARBALLS" ]
  then
    touch "$CURSRC/BUILD-TIMESTAMP" || dienow
    TIME=$(date +%s)
    while true
    do
      [ $TIME != "$(date +%s)" ] && break
      sleep .1
    done
  fi
}

# Given a filename.tar.ext, return the version number.

getversion()
{
  echo "$1" | sed -e 's/.*-\(\([0-9\.]\)*\([_-]rc\)*\(-pre\)*\([0-9][a-zA-Z]\)*\)*\(\.tar\..z2*\)$/'"$2"'\1/'
}

# Figure out what version of a package we last built

get_download_version()
{
  getversion $(sed -n 's@URL=.*/\(.[^ ]*\).*@\1@p' "$TOP/download.sh" | grep ${1}-)
}

# Identify subversion or mercurial revision, or release number

identify_release()
{
  DIR="$SRCDIR/$1"
  if [ -d "$DIR" ]
  then
    (
      cd "$DIR" || dienow
      ID="$(git log -1 --format=%H 2>/dev/null)"
      [ ! -z "$ID" ] && echo git "$ID" && return

      ID="$(hg identify -n 2>/dev/null)"
      [ ! -z "$ID" ] && echo hg "$ID" && return

      ID="$(svn info 2>/dev/null | sed -n "s/^Revision: //p")"
      [ ! -z "$ID" ] && echo svn "$ID" && return
    )
  fi

  echo release version $(get_download_version $1)
}

# Create a README identifying package versions in current build.

do_manifest()
{
  # Grab build script version number

  [ -z "$SCRIPT_VERS" ] &&
    SCRIPT_VERS="mercurial rev $(cd "$TOP"; hg identify -n 2>/dev/null)"

  cat << EOF
Built on $(date +%F) from:

  Build script:
    Aboriginal Linux (http://landley.net/aboriginal) $SCRIPT_VERS

  Base packages:
    uClibc (http://uclibc.org) $(identify_release uClibc)
    BusyBox (http://busybox.net) $(identify_release busybox)
    Linux (http://kernel.org/pub/linux/kernel) $(identify_release linux)
    toybox (http://landley.net/toybox) $(identify_release toybox)

  Toolchain packages:
    Binutils (http://www.gnu.org/software/binutils/) $(identify_release binutils)
    GCC (http://gcc.gnu.org) $(identify_release gcc-core)
    gmake (http://www.gnu.org/software/make) $(identify_release make)
    bash (ftp://ftp.gnu.org/gnu/bash) $(identify_release bash)

  Optional packages:
    distcc (http://distcc.samba.org) $(identify_release distcc)
    uClibc++ (http://cxx.uclibc.org) $(identify_release uClibc++)
EOF
}

# When building with a base architecture, symlink to the base arch name.

link_arch_name()
{
  [ "$ARCH" == "$ARCH_NAME" ] && return 0

  rm -rf "$BUILD/$2" &&
  ln -s "$1" "$BUILD/$2" || dienow
}

# Check if this target has a base architecture that's already been built.
# If so, link to it and exit now.

check_for_base_arch()
{
  # If we're building something with a base architecture, symlink to actual
  # target.

  if [ "$ARCH" != "$ARCH_NAME" ]
  then
    link_arch_name $STAGE_NAME-{"$ARCH","$ARCH_NAME"}
    [ -e $STAGE_NAME-"$ARCH".tar.gz ] &&
      link_arch_name $STAGE_NAME-{"$ARCH","$ARCH_NAME"}.tar.gz

    if [ -e "$BUILD/$STAGE_NAME-$ARCH" ]
    then
      announce "Using existing ${STAGE_NAME}-$ARCH"

      return 1
    else
      mkdir -p "$BUILD/$STAGE_NAME-$ARCH" || dienow
    fi
  fi
}

create_stage_tarball()
{
  # Remove the temporary directory, if empty

  rmdir "$WORK" 2>/dev/null

  # Handle linking to base architecture if we just built a derivative target.

  cd "$BUILD" || dienow
  link_arch_name $STAGE_NAME-{$ARCH,$ARCH_NAME}

  if [ -z "$NO_STAGE_TARBALLS" ]
  then
    echo -n creating "$STAGE_NAME-${ARCH}".tar.gz

    { tar czvf "$STAGE_NAME-${ARCH}".tar.gz "$STAGE_NAME-${ARCH}" || dienow
    } | dotprogress

    link_arch_name $STAGE_NAME-{$ARCH,$ARCH_NAME}.tar.gz
  fi
}

# Create colon-separated path for $HOSTTOOLS and all fallback directories
# (Fallback directories are to support ccache and distcc on the host.)

hosttools_path()
{
  local X

  echo -n "$HOSTTOOLS"
  X=1
  while [ -e "$HOSTTOOLS/fallback-$X" ]
  do
    echo -n ":$HOSTTOOLS/fallback-$X"
    X=$[$X+1]
  done
}

# Archive directory $1 to file $2 (plus extension), type SYSIMAGE_TYPE

image_filesystem()
{
  echo "make $SYSIMAGE_TYPE $2"

  # Embed an initramfs cpio

  if [ "$SYSIMAGE_TYPE" == "cpio" ] || [ "$SYSIMAGE_TYPE" == "rootfs" ]
  then
    # Borrow gen_init_cpio.c out of package cache copy of Linux source
    extract_package linux &&
    $CC "$(package_cache $PACKAGE)/usr/gen_init_cpio.c" -o "$WORK"/my_gen_init_cpio ||
      dienow
    "$WORK"/my_gen_init_cpio <(
        "$SOURCES"/toys/gen_initramfs_list.sh "$1" || dienow
        [ ! -e "$1"/init ] &&
          echo "slink /init /sbin/init.sh 755 0 0"
        [ ! -d "$1"/dev ] && echo "dir /dev 755 0 0"
        echo "nod /dev/console 660 0 0 c 5 1"
      ) | gzip -9 > "$2.cpio.gz" || dienow
    echo Initramfs generated.

  elif [ "$SYSIMAGE_TYPE" == "ext2" ] || [ "$SYSIMAGE_TYPE" == "ext3" ]
  then
    # Generate axn ext2 filesystem image from the $1 directory, with a
    # temporary file defining the /dev nodes for the new filesystem.

    [ -z "$SYSIMAGE_HDA_MEGS" ] && SYSIMAGE_HDA_MEGS=64

    # Produce a filesystem with the currently used space plus 20% for filesystem
    # overhead, which should always be big enough.

    BLOCKS=$[1024*(($(du -m -s "$1" | awk '{print $1}')*12)/10)]
    [ $BLOCKS -lt 4096 ] && BLOCKS=4096
    FILE="$2.$SYSIMAGE_TYPE"

    echo "/dev d 755 0 0 - - - - -" > "$WORK/devs" &&
    echo "/dev/console c 640 0 0 5 1 0 0 -" >> "$WORK/devs" &&
    genext2fs -z -D "$WORK/devs" -d "$1" -b $BLOCKS -i 1024 "$FILE" &&
    rm "$WORK/devs" || dienow

    # Extend image size to HDA_MEGS if necessary, keeping it sparse.  (Feeding
    # a larger -b size to genext2fs is insanely slow, and not particularly
    # sparse.)

    if [ ! -z "$SYSIMAGE_HDA_MEGS" ] &&
       [ $((`stat -c %s "$FILE"` / (1024*1024) )) -lt "$SYSIMAGE_HDA_MEGS" ]
    then
      echo resizing image to $SYSIMAGE_HDA_MEGS
      resize2fs "$FILE" ${SYSIMAGE_HDA_MEGS}M || dienow
    fi

    tune2fs -c 0 -i 0 $([ "$SYS_IMAGE_TYPE" = "ext3" ] && echo -j) "$FILE" || dienow
    echo $SYSIMAGE_TYPE generated

  elif [ "$SYSIMAGE_TYPE" == "squashfs" ]
  then
    mksquashfs "$1" "$2.sqf" -noappend -all-root ${FORK:+-no-progress} || dienow
  else
    echo "Unknown image type $SYSIMAGE_TYPE" >&2
    dienow
  fi
}
