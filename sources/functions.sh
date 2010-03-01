#!/bin/echo "This file is sourced, not run"

# Lots of reusable functions.  This file is sourced, not run.

source sources/utility_functions.sh

# Output the first cross compiler (static or basic) that's installed.

cc_path()
{
  local i

  for i in "$BUILD"/{,simple-}cross-compiler-"$1/bin"
  do
    [ -e "$i/$1-cc" ] && break
  done
  echo -n "$i:"
}

function read_arch_dir()
{
  # Get target platform from first command line argument.

  ARCH_NAME="$1"
  if [ ! -f "${SOURCES}/targets/${ARCH_NAME}/settings" ]
  then
    echo "Supported architectures: "
    (cd "${SOURCES}/targets" && ls)

    exit 1
  fi

  # Read the relevant config file.

  ARCH="$ARCH_NAME"
  CONFIG_DIR="${SOURCES}/targets"
  source "${CONFIG_DIR}/${ARCH}/settings"

  # Which platform are we building for?

  export WORK="${BUILD}/temp-$ARCH_NAME"

  # Say "unknown" in two different ways so it doesn't assume we're NOT
  # cross compiling when the host and target are the same processor.  (If host
  # and target match, the binutils/gcc/make builds won't use the cross compiler
  # during root-filesystem.sh, and the host compiler links binaries against the
  # wrong libc.)
  export_if_blank CROSS_HOST=`uname -m`-walrus-linux
  if [ -z "$CROSS_TARGET" ]
  then
    export CROSS_TARGET=${ARCH}-unknown-linux
  else
    [ -z "$FROM_HOST" ] && FROM_HOST="${CROSS_TARGET}"
  fi

  # Override FROM_ARCH to perform a canadian cross in root-filesystem.sh

  if [ -z "$FROM_ARCH" ]
  then
    FROM_ARCH="${ARCH}"
  else
    [ -z "$PROGRAM_PREFIX" ] && PROGRAM_PREFIX="${ARCH}-"
  fi
  export_if_blank FROM_HOST="${FROM_ARCH}-thingy-linux"

  # Setup directories and add the cross compiler to the start of the path.

  STAGE_DIR="$BUILD/${STAGE_NAME}-${ARCH_NAME}"

  export PATH="$(cc_path "$ARCH")$PATH"
  [ "$FROM_ARCH" != "$ARCH" ] && PATH="$(cc_path "$FROM_ARCH")$PATH"

  # Check this here because it could be set in "settings"

  [ ! -z "$BUILD_STATIC" ] && STATIC_FLAGS="--static"
  [ "$BUILD_STATIC" != none ] && STATIC_DEFAULT_FLAGS="--static"

  DO_CROSS="CROSS_COMPILE=${ARCH}-"

  return 0
}

# Note that this sources the file, rather than calling it as a separate
# process.  That way it can set environment variables if it wants to.

function build_section()
{
  if [ -e "$SOURCES/sections/$1".build ]
  then
    setupfor "$1"
    . "$SOURCES/sections/$1".build
    cleanup
  else
    echo "=== build section $1"
    . "$SOURCES"/sections/"$1".sh
  fi
}

# Figure out if we're using the stable or unstable versions of a package.

function unstable()
{
  [ ! -z "$(echo ,"$USE_UNSTABLE", | grep ,"$1",)" ]
}

# Find appropriate miniconfig file

function getconfig()
{
  for i in $(unstable $1 && echo {$ARCH_NAME,$ARCH}/miniconfig-alt-$1) \
    {$ARCH_NAME,$ARCH}/miniconfig-$1
  do
    if [ -f "$CONFIG_DIR/$i" ]
    then
      echo "$CONFIG_DIR/$i"
      return
    fi
  done

  echo "getconfig $1 failed" >&2
  dienow
}

# Find all files in $STAGE_DIR newer than $CURSRC.

function recent_binary_files()
{
  PREVIOUS=
  (cd "$STAGE_DIR" || dienow
   # Note $WORK/$PACKAGE != $CURSRC here for renamed packages like gcc-core.
   find . -depth -newer "$WORK/$PACKAGE/FWL-TIMESTAMP" \
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

# Strip the version number off a tarball

function cleanup()
{
  # If package build exited with an error, do not continue.

  [ $? -ne 0 ] && dienow

  if [ ! -z "$BINARY_PACKAGE_TARBALLS" ]
  then
    TARNAME="$PACKAGE-$STAGE_NAME-${ARCH_NAME}".tar.bz2
    echo -n Creating "$TARNAME"
    { recent_binary_files | xargs -0 tar -cjvf \
        "$BUILD/${TARNAME}".tar.bz2 -C "$STAGE_DIR" || dienow
    } | dotprogress
  fi

  if [ ! -z "$NO_CLEANUP" ]
  then
    echo "skip cleanup $PACKAGE $@"
    return
  fi

  # Loop deleting directories

  cd "$WORK" || dienow
  for i in "$PACKAGE" "$@"
  do
    [ -z "$i" ] && continue
    echo "cleanup $i"
    rm -rf "$i" || dienow
 done
}

# Give filename.tar.ext minus the version number.

function noversion()
{
  echo "$1" | sed -e 's/-*\(\([0-9\.]\)*\([_-]rc\)*\(-pre\)*\([0-9][a-zA-Z]\)*\)*\(\.tar\..z2*\)$/'"$2"'\6/'
}

# Given a filename.tar.ext, return the versino number.

function getversion()
{
  echo "$1" | sed -e 's/.*-\(\([0-9\.]\)*\([_-]rc\)*\(-pre\)*\([0-9][a-zA-Z]\)*\)*\(\.tar\..z2*\)$/'"$2"'\1/'
}

# Give package name, minus file's version number and archive extension.

function basename()
{
  noversion $1 | sed 's/\.tar\..z2*$//'
}

# Extract tarball named in $1 and apply all relevant patches into
# "$BUILD/packages/$1".  Record sha1sum of tarball and patch files in
# sha1-for-source.txt.  Re-extract if tarball or patches change.

function extract()
{
  FILENAME="$1"
  SHA1FILE="$(echo "${SRCTREE}/${PACKAGE}/sha1-for-source.txt")"

  # Sanity check: don't ever "rm -rf /".  Just don't.

  if [ -z "$PACKAGE" ] || [ -z "$SRCTREE" ]
  then
    dienow
  fi

  # If the source tarball doesn't exist, but the extracted directory is there,
  # assume everything's ok.

  [ ! -e "$FILENAME" ] && [ -e "$SHA1FILE" ] && return 0

  SHA1TAR="$(sha1file "${SRCDIR}/${FILENAME}")"

  # If it's already extracted and up to date (including patches), do nothing.
  SHALIST=$(cat "$SHA1FILE" 2> /dev/null)
  if [ ! -z "$SHALIST" ]
  then
    for i in "$SHA1TAR" $(sha1file "$PATCHDIR/${PACKAGE}"-* 2>/dev/null)
    do
      # Is this sha1 in the file?
      if [ -z "$(echo "$SHALIST" | sed -n "s/$i/$i/p" )" ]
      then
        SHALIST=missing
        break
      fi
      # Remove it
      SHALIST="$(echo "$SHALIST" | sed "s/$i//" )"
    done
    # If we matched all the sha1sums, nothing more to do.
    [ -z "$SHALIST" ] && return 0
  fi

  # Is it a bzip2 or gzip tarball?
  DECOMPRESS=""
  [ "$FILENAME" != "${FILENAME/%\.tar\.bz2/}" ] && DECOMPRESS="j"
  [ "$FILENAME" != "${FILENAME/%\.tar\.gz/}" ] && DECOMPRESS="z"

  echo -n "Extracting '${PACKAGE}'"

  (
    UNIQUE=$(readlink /proc/self)
    trap 'rm -rf "$BUILD/temp-'$UNIQUE'"' EXIT
    # Delete the old tree (if any).
    rm -rf "${SRCTREE}/${PACKAGE}" 2>/dev/null
    mkdir -p "${BUILD}"/{temp-$UNIQUE,packages} || dienow

    { tar -xv${DECOMPRESS} -f "${SRCDIR}/${FILENAME}" -C "${BUILD}/temp-$UNIQUE" ||
      dienow
    } | dotprogress

    mv "${BUILD}/temp-$UNIQUE/"* "${SRCTREE}/${PACKAGE}" &&
    echo "$SHA1TAR" > "$SHA1FILE"
  )

  [ $? -ne 0 ] && dienow

  # Apply any patches to this package

  ls "$PATCHDIR/${PACKAGE}"-* 2> /dev/null | sort | while read i
  do
    if [ -f "$i" ]
    then
      echo "Applying $i"
      (cd "${SRCTREE}/${PACKAGE}" && patch -p1 -i "$i") || dienow
      sha1file "$i" >> "$SHA1FILE"
    fi
  done
}

# Confirm that a file has the appropriate checksum (or exists but SHA1 is blank)
# Delete invalid file.

function confirm_checksum()
{
  SUM="$(sha1file "$SRCDIR/$FILENAME" 2>/dev/null)"
  if [ x"$SUM" == x"$SHA1" ] || [ -z "$SHA1" ] && [ -f "$SRCDIR/$FILENAME" ]
  then
    if [ -z "$SHA1" ]
    then
      echo "No SHA1 for $FILENAME ($SUM)"
    else
      echo "Confirmed $FILENAME"
    fi

    # Preemptively extract source packages?

    [ -z "$EXTRACT_ALL" ] && return 0
    EXTRACT_ONLY=1 setupfor "$(basename "$FILENAME")"
    return $?
  fi

  # If there's a corrupted file, delete it.  In theory it would be nice
  # to resume downloads, but wget creates "*.1" files instead.

  rm "$SRCDIR/$FILENAME" 2> /dev/null

  return 1
}

# Attempt to obtain file from a specific location

function download_from()
{
  # Return success if we already have a valid copy of the file

  confirm_checksum && return 0

  # If we have another source, try to download file from there.

  [ -z "$1" ] && return 1
  wget -t 2 -T 20 -O "$SRCDIR/$FILENAME" "$1" ||
    (rm "$SRCDIR/$FILENAME"; return 2)
  touch -c "$SRCDIR/$FILENAME"

  confirm_checksum
}

# Confirm a file matches sha1sum, else try to download it from mirror list.

function download()
{
  FILENAME=`echo "$URL" | sed 's .*/  '`
  [ -z "$RENAME" ] || FILENAME="$(echo "$FILENAME" | sed -r "$RENAME")"
  ALTFILENAME=alt-"$(noversion "$FILENAME" -0)"

  echo -ne "checking $FILENAME\r"

  # Update timestamps on both stable and unstable tarballs (if any)
  # so cleanup_oldfiles doesn't delete stable when we're building unstable
  # or vice versa

  touch -c "$SRCDIR"/{"$FILENAME","$ALTFILENAME"} 2>/dev/null

  # If unstable version selected, try from listed location, and fall back
  # to PREFERRED_MIRROR.  Do not try normal mirror locations for unstable.

  if unstable "$(basename "$FILENAME")"
  then
    FILENAME="$ALTFILENAME"
    SHA1=
    # Download new one as alt-packagename.tar.ext
    download_from "$UNSTABLE" ||
      ([ ! -z "$PREFERRED_MIRROR" ] &&
        download_from "$PREFERRED_MIRROR/$ALTFILENAME")
    return $?
  fi

  # If environment variable specifies a preferred mirror, try that first.

  if [ ! -z "$PREFERRED_MIRROR" ]
  then
    download_from "$PREFERRED_MIRROR/$FILENAME" && return 0
  fi

  # Try original location, then mirrors.
  # Note: the URLs in mirror list cannot contain whitespace.

  download_from "$URL" && return 0
  for i in $MIRROR_LIST
  do
    download_from "$i/$FILENAME" && return 0
  done

  # Return failure.

  echo "Could not download $FILENAME"
  echo -en "\e[0m"
  return 1
}

# Clean obsolete files out of the source directory

START_TIME=`date +%s`

function cleanup_oldfiles()
{
  for i in "${SRCDIR}"/*
  do
    if [ -f "$i" ] && [ "$(date +%s -r "$i")" -lt "${START_TIME}" ]
    then
      echo Removing old file "$i"
      rm -rf "$i"
    fi
  done
}

# Extract package $1, use out-of-tree build directory $2 (or $1 if no $2)
# Use link directory $3 (or $1 if no $3)

function setupfor()
{
  export WRAPPY_LOGPATH="$BUILD/logs/cmdlines.${ARCH_NAME}.${STAGE_NAME}.setupfor"

  # Figure out whether we're using an unstable package.

  PACKAGE="$1"
  unstable "$PACKAGE" && PACKAGE=alt-"$PACKAGE"

  # Make sure the source is already extracted and up-to-date.
  cd "${SRCDIR}" &&
  extract "${PACKAGE}-"*.tar* || exit 1

  # If all we want to do is extract source, bail out now.
  [ ! -z "$EXTRACT_ONLY" ] && return 0

  # Set CURSRC
  CURSRC="$PACKAGE"
  if [ ! -z "$3" ]
  then
    CURSRC="$3"
    unstable "$CURSRC" && CURSRC=alt-"$CURSRC"
  fi
  export CURSRC="${WORK}/${CURSRC}"

  [ -z "$SNAPSHOT_SYMLINK" ] && LINKTYPE="l" || LINKTYPE="s"

  # Announce package, with easy-to-grep-for "===" marker.

  echo "=== Building $PACKAGE ($ARCH_NAME $STAGE_NAME)"
  echo "Snapshot '$PACKAGE'..."
  cd "${WORK}" || dienow
  if [ $# -lt 3 ]
  then
    rm -rf "${CURSRC}" || dienow
  fi
  mkdir -p "${CURSRC}" &&
  cp -${LINKTYPE}fR "${SRCTREE}/$PACKAGE/"* "${CURSRC}"

  [ $? -ne 0 ] && dienow

  # Do we have a separate working directory?

  if [ -z "$2" ]
  then
    cd "$PACKAGE"* || dienow
  else
    mkdir -p "$2" && cd "$2" || dienow
  fi
  export WRAPPY_LOGPATH="$BUILD/logs/cmdlines.${ARCH_NAME}.${STAGE_NAME}.$1"

  # Change window title bar to package now
  set_titlebar "$ARCH_NAME $STAGE_NAME $PACKAGE"

  # Ugly bug workaround: timestamp granularity in a lot of filesystems is only
  # 1 second, so find -newer misses things installed in the same second, so we
  # make sure it's a new second before we start actually doing anything.

  if [ ! -z "$BINARY_PACKAGE_TARBALLS" ]
  then
    touch "${CURSRC}/FWL-TIMESTAMP" || dienow
    TIME=$(date +%s)
    while true
    do
      [ $TIME != "$(date +%s)" ] && break
      sleep .1
    done
  fi
}

# Figure out what version of a package we last built

function get_download_version()
{
  getversion $(sed -n 's@URL=.*/\(.[^ ]*\).*@\1@p' "$TOP/download.sh" | grep ${1}-)
}

# Identify subversion or mercurial revision, or release number

function identify_release()
{
  if unstable "$1"
  then
    for i in "b" ""
    do
      FILE="$(echo "$SRCDIR/alt-$1-"*.tar.$i*)"
      if [ -f "$FILE" ]
      then
        GITID="$(${i}zcat "$FILE" | git get-tar-commit-id)"
        if [ ! -z "$GITID" ]
        then
          # The first dozen chars should form a unique id.

          echo $GITID | sed 's/^\(................\).*/git \1/'
          return
        fi
      fi
    done

    # Need to extract unstable packages to determine source control version.

    EXTRACT_ONLY=1 setupfor "$1" >&2
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

function do_readme()
{
  # Grab FWL version number

  [ -z "$FWL_VERS" ] &&
    FWL_VERS="mercurial rev $(cd "$TOP"; hg tip 2>/dev/null | sed -n 's/changeset: *\([0-9]*\).*/\1/p')"

  cat << EOF
Built on $(date +%F) from:

  Build script:
    Firmware Linux (http://landley.net/code/firmware) $FWL_VERS

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
    Toybox (http://landley.net/code/toybox) $(identify_release toybox)
    distcc (http://distcc.samba.org) $(identify_release distcc)
    uClibc++ (http://cxx.uclibc.org) $(identify_release uClibc++)
EOF
}

# When building with a base architecture, symlink to the base arch name.

function link_arch_name()
{
  [ "$ARCH" == "$ARCH_NAME" ] && return 0

  rm -rf "$BUILD/$2" &&
  ln -s "$1" "$BUILD/$2" || dienow
}

# Check if this target has a base architecture that's already been built.
# If so, link to it and exit now.

function check_for_base_arch()
{
  blank_tempdir "$STAGE_DIR"
  blank_tempdir "$WORK"

  # If we're building something with a base architecture, symlink to actual
  # target.

  if [ "$ARCH" != "$ARCH_NAME" ]
  then
    link_arch_name $STAGE_NAME-{"$ARCH","$ARCH_NAME"}
    [ -e $STAGE_NAME-"$ARCH".tar.bz2 ] &&
      link_arch_name $STAGE_NAME-{"$ARCH","$ARCH_NAME"}.tar.bz2

    if [ -e "$BUILD/$STAGE_NAME-$ARCH" ]
    then
      echo "=== Using existing ${STAGE_NAME}-$ARCH"

      return 1
    else
      mkdir -p "$BUILD/$STAGE_NAME-$ARCH" || dienow
    fi
  fi
}

function create_stage_tarball()
{
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

function hosttools_path()
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
