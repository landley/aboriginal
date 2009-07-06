#!/bin/bash

#export PREFERRED_MIRROR=http://impactlinux.com/fwl/mirror
#FWL_STABLE=tip

TOP="$(pwd)"
SNAPSHOT_DATE=$(date +"%Y-%m-%d")

TEMPDIR="$TOP"

rm -rf triage.* build

# Update each package from repository, generate alt-tarball, and build with
# that package.

for PACKAGE in none $PACKAGES all
do
  export USE_UNSTABLE="$PACKAGE"

  # Handle special package name "all"

  if [ "$PACKAGE" == "none" ]
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
  FORK=1 nice -n 20 ./buildall.sh

  FORK=1 ./smoketest-all.sh --logs > build/logs/status.txt

  DESTDIR="$TOP/../snapshots/$PACKAGE/$SNAPSHOT_DATE"
  rm -rf "$DESTDIR"
  mkdir -p "$DESTDIR"
  mv build/logs build/*.tar.bz2 "$DESTDIR"
  mv build "$TEMPDIR/triage.$PACKAGE"
done
