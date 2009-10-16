#!/bin/bash

# This script is run by a nightly cron job to build snapshots using the current
# build scripts from the repository.

# It builds a "stable" version of each architecture using stable version of all
# packages (according to the current ./download.sh), and then iterates through
# the packages listed in $PACKAGES grabbing a repository snapshot of each one
# and building each architecture again.  Finally, it builds an "all" version
# using the unstable versions of every listed package simultaneously.

# The cron job is run under a dedicated user, and invokes this script via the
# following code snippet:

#   cd firmware
#   hg pull -u
#   export PREFERRED_MIRROR=http://impactlinux.com/fwl/mirror
#   export PACKAGES="busybox uClibc linux"
#   sources/more/cronjob.sh >/dev/null 2>/dev/null </dev/null
#   /rsync_to_server.sh

# The dedicated user's home directory has ~/{firmware,busybox,uClibc,linux}
# directories at the top level, containing appropriate repositories.
# The firmware repository is updated externally (since you don't want to run
# a script out of a repository you're updating).  The other three ones updated
# by this script.  (It currently only understands git repositories, out of
# sheer laziness.)
#
# The ~/snapshot directory is used to store output, and then rsynced up to
# the server

# This script calls sources/more/buildall.sh

TOP="$(pwd)"
SNAPSHOT_DATE=$(date +"%Y-%m-%d")

TEMPDIR="$TOP"

rm -rf triage.* build

# Update each package from repository, generate alt-tarball, and build with
# that package.

for PACKAGE in stable $PACKAGES all
do
  export USE_UNSTABLE="$PACKAGE"

  # Handle special package name "all"

  if [ "$PACKAGE" == "stable" ]
  then
    USE_UNSTABLE=
  elif [ "$PACKAGE" == "all" ]
  then
    [ -z "$PACKAGES" ] && continue

    USE_UNSTABLE="$(echo "$PACKAGES" | sed 's/ /,/')"

  # Update package from repository

  else
    cd "$TOP/../$PACKAGE"
    echo updating "$PACKAGE"
    git pull
    git archive master --prefix=$PACKAGE/ | bzip2 > \
      "$TOP"/packages/alt-$PACKAGE-0.tar.bz2
  fi

  # Build everything with unstable version of that package, and stable
  # version of everything else (including build scripts).

  cd "$TOP"
  FORK=1 nice -n 20 sources/more/buildall.sh

  # Move results to output directory.

  DESTDIR="$TOP/../snapshots/$PACKAGE/$SNAPSHOT_DATE"
  rm -rf "$DESTDIR"
  mkdir -p "$DESTDIR"
  mv build/logs build/*.tar.bz2 "$DESTDIR"
  mv build "$TEMPDIR/triage.$PACKAGE"
done
