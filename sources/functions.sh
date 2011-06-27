#!/bin/echo "This file is sourced, not run"

# Lots of reusable functions.  This file is sourced, not run.

# Output path to cross compiler.

cc_path()
{
  local i

  # Output cross it if exists, else simple.  If neither exists, output simple.

  for i in "$BUILD"/{,simple-}cross-compiler-"$1/bin"
  do
    [ -e "$i/$1-cc" ] && break
  done
  echo -n "$i:"
}

load_target()
{
  # Get target platform from first command line argument.

  ARCH_NAME="$1"
  ARCH="$ARCH_NAME"
  CONFIG_DIR="$SOURCES/targets"

  # Read the relevant config file.

  if [ -f "$CONFIG_DIR/$ARCH" ]
  then
    source "$CONFIG_DIR/$ARCH"
    CONFIG_DIR=
  elif [ -f "$CONFIG_DIR/$ARCH/settings" ]
  then
    source "$CONFIG_DIR/$ARCH/settings" ]
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

  blank_tempdir "$STAGE_DIR"
  blank_tempdir "$WORK"

  export PATH="$(cc_path "$ARCH")$PATH"
  [ ! -z "$HOST_ARCH" ] && [ "$HOST_ARCH" != "$ARCH" ] &&
    PATH="$(cc_path "$HOST_ARCH")$PATH"

  DO_CROSS="CROSS_COMPILE=${ARCH}-"

  return 0
}

# Note that this sources the file, rather than calling it as a separate
# process.  That way it can set environment variables if it wants to.

build_section()
{
  # Don't build anything statically in host-tools, glibc is broken.
  # See http://people.redhat.com/drepper/no_static_linking.html for
  # insane rant from the glibc maintainer about why he doesn't care.
  is_in_list $1 $BUILD_STATIC && [ ! -z "$ARCH" ] && STATIC_FLAGS="--static"

  OLDCPUS=$CPUS
  is_in_list $1 $DEBUG_PACKAGE && CPUS=1

  if [ -e "$SOURCES/sections/$1".build ]
  then
    setupfor "$1"
    . "$SOURCES/sections/$1".build
    cleanup
  else
    announce "$1"
    . "$SOURCES"/sections/"$1".sh
  fi
  CPUS=$OLDCPUS
}

# Find appropriate miniconfig file

getconfig()
{
  for i in $(is_in_list $1 $USE_UNSTABLE && echo {$ARCH_NAME,$ARCH}/miniconfig-alt-$1) \
    {$ARCH_NAME,$ARCH}/miniconfig-$1
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
    TARNAME="$PACKAGE-$STAGE_NAME-${ARCH_NAME}".tar.bz2
    [ ! -z "$(recent_binary_files)" ] &&
      echo -n Creating "$TARNAME" &&
      { recent_binary_files | xargs -0 tar -cjvf \
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

setupfor()
{
  export WRAPPY_LOGPATH="$BUILD/logs/cmdlines.${ARCH_NAME}.${STAGE_NAME}.setupfor"

  # Make sure the source is already extracted and up-to-date.
  extract_package "$1" || exit 1

  # Delete old working copy (even in the NO_CLEANUP case) then make a new
  # tree of links to the package cache.

  echo "Snapshot '$PACKAGE'..."

  if [ -z "$REUSE_CURSRC" ]
  then
    blank_workdir "$PACKAGE"
    CURSRC="$(pwd)"
  fi

  [ -z "$SNAPSHOT_SYMLINK" ] && LINKTYPE="l" || LINKTYPE="s"
  cp -${LINKTYPE}fR "$SRCTREE/$PACKAGE/"* "$CURSRC"

  if [ $? -ne 0 ]
  then
    echo "$PACKAGE not found.  Did you run download.sh?" >&2
    dienow
  fi

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
  if is_in_list "$1" $USE_UNSTABLE
  then
    for i in "b" ""
    do
      FILE="$(echo "$SRCDIR/alt-$1-"*.tar.$i*)"
      if [ -f "$FILE" ]
      then
        GITID="$(${i}zcat "$FILE" 2> /dev/null | git get-tar-commit-id 2>/dev/null)"
        if [ ! -z "$GITID" ]
        then
          # The first dozen chars should form a unique id.

          echo $GITID | sed 's/^\(................\).*/git \1/'
          return
        fi
      fi
    done

    # Need to extract unstable packages to determine source control version.

    extract_package "$1" >&2
    DIR="${BUILD}/packages/alt-$1"

    if [ -d "$DIR/.svn" ]
    then
      ( cd "$DIR"; echo subversion rev \
        $(svn info | sed -n "s/^Revision: //p")
      )
      return 0
    elif [ -d "$DIR/.hg" ]
    then
      ( echo mercurial rev \
          $(hg tip | sed -n 's/changeset: *\([0-9]*\).*/\1/p')
      )
      return 0
    fi
  fi

  echo release version $(get_download_version $1)
}

# Create a README identifying package versions in current build.

do_manifest()
{
  # Grab build script version number

  [ -z "$SCRIPT_VERS" ] &&
    SCRIPT_VERS="mercurial rev $(cd "$TOP"; hg tip 2>/dev/null | sed -n 's/changeset: *\([0-9]*\).*/\1/p')"

  cat << EOF
Built on $(date +%F) from:

  Build script:
    Aboriginal Linux (http://landley.net/aboriginal) $SCRIPT_VERS

  Base packages:
    uClibc (http://uclibc.org) $(identify_release uClibc)
    BusyBox (http://busybox.net) $(identify_release busybox)
    Linux (http://kernel.org/pub/linux/kernel) $(identify_release linux)

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
    [ -e $STAGE_NAME-"$ARCH".tar.bz2 ] &&
      link_arch_name $STAGE_NAME-{"$ARCH","$ARCH_NAME"}.tar.bz2

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
    echo -n creating "$STAGE_NAME-${ARCH}".tar.bz2

    { tar cjvf "$STAGE_NAME-${ARCH}".tar.bz2 "$STAGE_NAME-${ARCH}" || dienow
    } | dotprogress

    link_arch_name $STAGE_NAME-{$ARCH,$ARCH_NAME}.tar.bz2
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
