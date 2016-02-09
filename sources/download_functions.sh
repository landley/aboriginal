#!/bin/echo "This file is sourced, not run"

# Set of functions to download, extract, and patch source tarballs.
#
# Tools to populate and verify a directory of package source tarballs
# (saved in $SRCDIR which defaults to $TOP/packages). Used by download.sh.
#
#   You can supply your own tarball in $SRCDIR to avoid downloading it.
#
#   You can also provide an expanded directory (same filename as $URL
#   but no version or extension) to be used instead of a tarball. This is
#   usually a source control checkout.
#
#   $IGNORE_REPOS - comma separated list of package names (or "all") to
#     download tarballs for anyway, ignoring the directory version if present.
#
# Functions to call from here:
#
# download
#   - fetch a file (with wget) if it doesn't already exist, or doesn't match
#     checksum.
#
#   It expects you to set:
#     $URL - Default location of file, including filename
#     $SHA1 - sha1sum of good file. (Blank means accept any file.)
#
#   You can also set these (which use filename from $URL):
#     $PREFERRED_MIRROR - Check here first (appending filename from $URL)
#     $MIRROR_LIST - Space separated list of fallback locations (appending
#       filename from $URL) to check if default location didn't have it.
#
#   Does not re-download existing tarballs if the $SHA1 matches/is blank.
#   Does not download tarball if expanded directory present.
#
# cleanup_oldfiles
#   - remove stale files from $SRCDIR
#
#   Stale means not referenced by a download call since start of script.
#   Only affects files, not subdirectories.


# Remove version information and extension tarball name "$1".
# If "$2", add that version number back, keeping original extension.

noversion()
{
  LOGRUS='s/-*\(\([0-9\.]\)*\([_-]rc\)*\(-pre\)*\([0-9][a-zA-Z]\)*\)*\(\.tar\(\..z2*\)*\)$'
  [ -z "$2" ] && LOGRUS="$LOGRUS//" || LOGRUS="$LOGRUS/$2\\6/"

  echo "$1" | sed -e "$LOGRUS"
}

gather_patches()
{
  # Variant patches are found in the sources/patches-${variant} directory
  # instead of the regular path
  DIRECTORY=$PATCHDIR
  [ ! -z "${PACKAGE_VARIANT}" ] && DIRECTORY="${PATCHDIR}-${PACKAGE_VARIANT}"

  ls "$DIRECTORY/${PACKAGE}"-*.patch 2> /dev/null | sort | while read i
  do
    if [ -f "$i" ]
    then
      echo "$i"
    fi
  done

  # gather external package patches sorted by filename
  if [ ! -z "$MY_PATCH_DIR" ] && [ -d "${MY_PATCH_DIR}/${PACKAGE}" ]
  then
    for i in "${MY_PATCH_DIR}/${PACKAGE}/"*.patch
    do
      if [ -f "$i" ]
      then
        echo "$i"
      fi
    done
  fi
}

# Apply any patches to this package
patch_package()
{
  gather_patches | while read i
  do
    if [ -f "$i" ]
    then
      echo "Applying $i"
      (cd "${SRCTREE}/${PACKAGE}" &&
       patch -p1 -i "$i" &&
       sha1file "$i" >> "$SHA1FILE") ||
        if [ -z "$ALLOW_PATCH_FAILURE" ]
        then
          dienow
        fi
    fi
  done
}

# Get the tarball for this package

find_package_tarball()
{
  # If there are multiple similar files we want the newest timestamp, in case
  # the URL just got upgraded but cleanup_oldfiles hasn't run yet.  Be able to
  # distinguish "package-123.tar.bz2" from "package-tests-123.tar.bz2" and
  # return the shorter one reliably.

  ls -tc "$SRCDIR/$1-"*.tar* 2>/dev/null | while read i
  do
    if [ "$(noversion "${i/*\//}")" == "$1" ]
    then
      echo "$i"
      break
    fi
  done
}

package_cache()
{
  SNAPFROM="$SRCDIR/$1"
  (is_in_list "$1" "$IGNORE_REPOS" || [ ! -d "$SNAPFROM" ]) &&
    SNAPFROM="$SRCTREE/$1"

  if [ ! -d "$SNAPFROM" ]
  then
    echo "$1 not found.  Did you run download.sh?" >&2
    dienow
  fi

  echo "$SNAPFROM"
}

# Extract tarball named in $1 and apply all relevant patches into
# "$BUILD/packages/$1".  Record sha1sum of tarball and patch files in
# sha1-for-source.txt.  Re-extract if tarball or patches change.
#
# If $2 is specified it is a variant of the package, as such
# the variant name will be used as a basename for the patches instead
# of $1
extract_package()
{
  mkdir -p "$SRCTREE" || dienow

  PACKAGE="$1"
  [ -z "$2" ] && PACKAGE_VARIANT= || PACKAGE_VARIANT=$2

  # Announce to the world that we're cracking open a new package
  announce "$PACKAGE"

  ! is_in_list "PACKAGE" "$IGNORE_REPOS" && [ -d "$SRCDIR/$PACKAGE" ] &&
    return 0

  # Find tarball, and determine type

  FILENAME="$(find_package_tarball "$PACKAGE")"
  DECOMPRESS=""
  [ "$FILENAME" != "${FILENAME/%\.tar\.bz2/}" ] && DECOMPRESS="j"
  [ "$FILENAME" != "${FILENAME/%\.tar\.gz/}" ] && DECOMPRESS="z"

  # If the source tarball doesn't exist, but the extracted directory is there,
  # assume everything's ok.

  SHA1NAME="sha1-for-source.txt"
  SHA1FILE="$SRCTREE/$PACKAGE/$SHA1NAME"
  if [ -z "$FILENAME" ]
  then
    if [ ! -e "$SRCTREE/$PACKAGE" ]
    then
      echo "No tarball for $PACKAGE" >&2
      dienow
    fi

    # If the sha1sum file isn't there, re-patch the package.
    [ ! -e "$SHA1FILE" ] && patch_package
    return 0
  fi

  # Check the sha1 list from the previous extract.  If the source is already
  # up to date (including patches), keep it.

  SHA1TAR="$(sha1file "$FILENAME")"
  SHALIST=$(cat "$SHA1FILE" 2> /dev/null)
  if [ ! -z "$SHALIST" ]
  then
    for i in "$SHA1TAR" $(sha1file $(gather_patches))
    do
      # Is this sha1 in the file?
      if [ -z "$(echo "$SHALIST" | grep "$i")" ]
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

  # Re-extract the package, deleting the old one (if any)..

  echo -n "Extracting '$PACKAGE'"
  (
    UNIQUE=$(readlink /proc/self)
    trap 'rm -rf "$BUILD/temp-'$UNIQUE'"' EXIT
    rm -rf "$SRCTREE/$PACKAGE" 2>/dev/null
    mkdir -p "$BUILD/temp-$UNIQUE" "$SRCTREE" || dienow

    { tar -xv${DECOMPRESS} -f "$FILENAME" -C "$BUILD/temp-$UNIQUE" &&
      # Wildcards only expand when they ponit to something that exists,
      # and even then they have to be an argument to a command.
      TARDIR="$(readlink -f "$BUILD/temp-$UNIQUE"/*)" &&
      touch "$TARDIR/$SHA1NAME"
    } | dotprogress

    [ -e "$BUILD/temp-$UNIQUE"/*/"$SHA1NAME" ] &&
    mv "$BUILD/temp-$UNIQUE/"* "$SRCTREE/$PACKAGE" &&
    echo "$SHA1TAR" >> "$SHA1FILE"
  )

  [ $? -ne 0 ] && dienow

  patch_package
}

# Confirm that a file has the appropriate checksum (or exists but SHA1 is blank)
# Delete invalid file.

confirm_checksum()
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
    extract_package "$BASENAME"
    return $?
  fi

  # If there's a corrupted file, delete it.  In theory it would be nice
  # to resume downloads, but wget creates "*.1" files instead.

  rm -f "$SRCDIR/$FILENAME"

  return 1
}

# Attempt to obtain file from a specific location

download_from()
{
  # Return success if we already have a valid copy of the file

  confirm_checksum && return 0

  # If we have another source, try to download file from there.

  [ -z "$1" ] && return 1
  wget -t 2 -T 20 -O "$SRCDIR/$FILENAME" "$1" ||
    (rm -f "$SRCDIR/$FILENAME"; return 2)
  touch -c "$SRCDIR/$FILENAME"

  confirm_checksum
}

# Confirm a file matches sha1sum, else try to download it from mirror list.

download()
{
  FILENAME=`echo "$URL" | sed 's .*/  '`
  [ -z "$RENAME" ] || FILENAME="$(echo "$FILENAME" | sed -r "$RENAME")"

  if [ -z "$(sha1sum < /dev/null)" ]
  then
    echo "Error: please install sha1sum" >&2
    exit 1
  fi

  echo -ne "checking $FILENAME\r"

  # Update timestamp on tarball (if it exists) so cleanup_oldfiles keeps it

  touch -c "$SRCDIR"/"$FILENAME" 2>/dev/null

  # Give package name, minus file's version number and archive extension.
  BASENAME="$(noversion "$FILENAME")"
  if ! is_in_list "$BASENAME" "$IGNORE_REPOS" && [ -d "$SRCDIR/$BASENAME" ]
  then
    echo "Using $SRCDIR/$BASENAME"
    if [ "$EXTRACT_ALL" == force ]
    then
      rm -rf "$SRCTREE/$BASENAME" &&
      cp -a "$SRCDIR/$BASENAME" "$SRCTREE/$BASENAME" || dienow
    fi

    return 0
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

cleanup_oldfiles()
{
  # wait for asynchronous downloads to complete

  wait

  for i in "${SRCDIR}"/*
  do
    if [ -f "$i" ] && [ "$(date +%s -r "$i")" -lt "${START_TIME}" ]
    then
      echo Removing old file "$i"
      rm -rf "$i"
    fi
  done
}
