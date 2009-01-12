# Lots of reusable functions.  This file is sourced, not run.

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

# Strip the version number off a tarball

function cleanup()
{

  [ $? -ne 0 ] && dienow

  if [ ! -z "$NO_CLEANUP" ]
  then
    echo "skip cleanup $@"
    return
  fi

  for i in "$@"
  do
    unstable "$i" && i="$PACKAGE"
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

# output the sha1sum of a file
function sha1file()
{
  sha1sum "$@" | awk '{print $1}'
}

# Extract tarball named in $1 and apply all relevant patches into
# "$BUILD/sources/$1".  Record sha1sum of tarball and patch files in
# sha1-for-source.txt.  Re-extract if tarball or patches change.

function extract()
{
  SRCTREE="${BUILD}/sources"
  BASENAME="$(basename "$1")"
  SHA1FILE="$(echo "${SRCTREE}/${BASENAME}/sha1-for-source.txt")"
  SHA1TAR="$(sha1file "${SRCDIR}/$1")"

  # Sanity check: don't ever "rm -rf /".  Just don't.

  if [ -z "$BASENAME" ] || [ -z "$SRCTREE" ]
  then
    dienow
  fi

  # If it's already extracted and up to date (including patches), do nothing.
  SHALIST=$(cat "$SHA1FILE" 2> /dev/null)
  if [ ! -z "$SHALIST" ]
  then
    for i in "$SHA1TAR" $(sha1file "${SOURCES}/patches/$BASENAME"-* 2>/dev/null)
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

  echo -n "Extracting '${BASENAME}'"
  # Delete the old tree (if any).  Create new empty working directories.
  rm -rf "${BUILD}/temp" "${SRCTREE}/${BASENAME}" 2>/dev/null
  mkdir -p "${BUILD}"/{temp,sources} || dienow

  # Is it a bzip2 or gzip tarball?
  DECOMPRESS=""
  [ "$1" != "${1/%\.tar\.bz2/}" ] && DECOMPRESS="j"
  [ "$1" != "${1/%\.tar\.gz/}" ] && DECOMPRESS="z"

  cd "${WORK}" &&
  { tar -xv${DECOMPRESS} -f "${SRCDIR}/$1" -C "${BUILD}/temp" || dienow
  } | dotprogress

  mv "${BUILD}/temp/"* "${SRCTREE}/${BASENAME}" &&
  rmdir "${BUILD}/temp" &&
  echo "$SHA1TAR" > "$SHA1FILE"

  [ $? -ne 0 ] && dienow

  # Apply any patches to this package

  ls "${SOURCES}/patches/$BASENAME"-* 2> /dev/null | sort | while read i
  do
    if [ -f "$i" ]
    then
      echo "Applying $i"
      (cd "${SRCTREE}/${BASENAME}" && patch -p1 -i "$i") || dienow
      sha1file "$i" >> "$SHA1FILE"
    fi
  done
}

function try_checksum()
{
  SUM="$(sha1file "$SRCDIR/$FILENAME" 2>/dev/null)"
  if [ x"$SUM" == x"$SHA1" ] || [ -z "$SHA1" ] && [ -f "$SRCDIR/$FILENAME" ]
  then
    touch "$SRCDIR/$FILENAME"
    if [ -z "$SHA1" ]
    then
      echo "No SHA1 for $FILENAME ($SUM)"
    else
      echo "Confirmed $FILENAME"
    fi

    [ -z "$EXTRACT_ALL" ] && return 0
    extract "$FILENAME"
    return $?
  fi

  return 1
}


function try_download()
{
  # Return success if we have a valid copy of the file

  try_checksum && return 0

  # If there's a corrupted file, delete it.  In theory it would be nice
  # to resume downloads, but wget creates "*.1" files instead.

  rm "$SRCDIR/$FILENAME" 2> /dev/null

  # If we have another source, try to download file.

  if [ -n "$1" ]
  then
    wget -t 2 -T 20 -O "$SRCDIR/$FILENAME" "$1" || return 2
  fi

  try_checksum
}

# Confirm a file matches sha1sum, else try to download it from mirror list.

function download()
{
  FILENAME=`echo "$URL" | sed 's .*/  '`
  ALTFILENAME=alt-"$(noversion "$FILENAME" -0)"

  # Is the unstable version selected?
  if unstable "$(basename "$FILENAME")"
  then
    # Keep old version around, if present.
    touch -c "$SRCDIR/$FILENAME" 2>/dev/null

    # Download new one as alt-packagename.tar.ext
    FILENAME="$ALTFILENAME" SHA1= try_download "$UNSTABLE"
    return $?
  fi

  # If environment variable specifies a preferred mirror, try that first.

  if [ ! -z "$PREFERRED_MIRROR" ]
  then
    try_download "$PREFERRED_MIRROR/$FILENAME" && return 0
  fi

  # Try standard locations

  for i in "$URL" http://impactlinux.com/firmware/mirror/"$FILENAME" \
    http://landley.net/code/firmware/mirror/"$FILENAME"
  do
    try_download "$i" && return 0
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

# An exit function that works properly even from a subshell.

function actually_dienow()
{
  echo -e "\e[31mExiting due to errors ($ARCH_NAME $STAGE_NAME $PACKAGE)\e[0m"
  exit 1
}

trap actually_dienow SIGUSR1
TOPSHELL=$$

function dienow()
{
  kill -USR1 $TOPSHELL
  exit 1
}

# Turn a bunch of output lines into a much quieter series of periods.

function dotprogress()
{
  x=0
  while read i
  do
    x=$[$x + 1]
    if [[ "$x" -eq 25 ]]
    then
      x=0
      echo -n .
    fi
  done
  echo
}

# Extract package $1, use out-of-tree build directory $2 (or $1 if no $2)
# Use link directory $3 (or $1 if no $3)

function setupfor()
{
  export WRAPPY_LOGPATH="$WRAPPY_LOGDIR/cmdlines.${STAGE_NAME}.setupfor"

  # Figure out whether we're using an unstable package.

  PACKAGE="$1"
  unstable "$PACKAGE" && PACKAGE=alt-"$PACKAGE"

  # Make sure the source is already extracted and up-to-date.
  cd "${SRCDIR}" &&
  extract "${PACKAGE}-"*.tar* || exit 1

  # Set CURSRC
  CURSRC="$PACKAGE"
  if [ ! -z "$3" ]
  then
    CURSRC="$3"
    unstable "$CURSRC" && CURSRC=alt-"$CURSRC"
  fi
  export CURSRC="${WORK}/${CURSRC}"

  # Announce package, with easy-to-grep-for "===" marker.

  echo "=== Building $PACKAGE ($ARCH_NAME)"
  echo "Snapshot '$PACKAGE'..."
  cd "${WORK}" || dienow
  if [ $# -lt 3 ]
  then
    rm -rf "${CURSRC}" || dienow
  fi
  mkdir -p "${CURSRC}" &&
  cp -lfR "${SRCTREE}/$PACKAGE/"* "${CURSRC}"

  [ $? -ne 0 ] && dienow

  # Do we have a separate working directory?

  if [ -z "$2" ]
  then
    cd "$PACKAGE"* || dienow
  else
    mkdir -p "$2" && cd "$2" || dienow
  fi
  export WRAPPY_LOGPATH="$WRAPPY_LOGDIR/cmdlines.${STAGE_NAME}.$1"

  # Change window title bar to package now
  echo -en "\033]2;$ARCH_NAME $STAGE_NAME $PACKAGE\007"
}

# usage: wait4background 0

function wait4background()
{
  local EXCLUDE="$2"
  [ -z "$EXCLUDE" ] && EXCLUDE="thisdoesnotmatchanything"
  # Wait for background tasks to finish
  while [ $(jobs | grep -v "$EXCLUDE" | wc -l) -gt $1 ]
  do
    sleep 1
    # Without this next line, bash never notices a change in the number of jobs.
    # Bug noticed in Ubuntu 7.04
    jobs > /dev/null
  done
}

# Figure out what version of a package we last built

function get_download_version()
{
  getversion $(sed -n 's@URL=.*/\(.[^ ]*\).*@\1@p' download.sh | grep ${1}-)
}

# Identify subversion or mercurial revision, or release number

function identify_release()
{
  if [ -d build/sources/alt-$1/.svn ]
  then
    echo subversion rev \
      $(svn info build/sources/alt-uClibc | sed -n "s/^Revision: //p")
  elif [ -d build/sources/alt-$1/.hg ]
  then
    echo mercurial rev \
      $(hg tip | sed -n 's/changeset: *\([0-9]*\).*/\1/p')
  else
    echo release version $(get_download_version $1)
  fi
}

# Create a README identifying package versions in current build.

function do_readme()
{
  # Grab FWL version number

  cat << EOF
These tarballs were built on $(date +%F) from:

  Build script:
    Firmware Linux (http://landley.net/code/firmware) mercurial rev $(hg tip | sed -n 's/changeset: *\([0-9]*\).*/\1/p')

  Base packages:
    uClibc (http://uclibc.org) $(identify_release uClibc)
    BusyBox (http://busybox.net) $(identify_release busybox)
    Linux (http://kernel.org/pub/linux/kernel) $(identify_release linux)

  Toolchain packages:
    Binutils (http://www.gnu.org/software/binutils/) $(identify_release binutils
)
    GCC (http://gcc.gnu.org) $(identify_release gcc-core)
    gmake (http://www.gnu.org/software/make) $(identify_release make)
    bash (ftp://ftp.gnu.org/gnu/bash) $(identify_release bash)

  Optional packages:
    Toybox (http://landley.net/code/toybox) $(identify_release toybox)
    distcc (http://distcc.samba.org) $(identify_release distcc)
    uClibc++ (http://cxx.uclibc.org) $(identify_release uClibc++)
EOF
}
