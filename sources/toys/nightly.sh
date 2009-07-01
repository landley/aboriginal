#!/bin/bash

#export PREFERRED_MIRROR=http://impactlinux.com/fwl/mirror
#FWL_STABLE=tip

TOP="$(pwd)"
SNAPSHOT_DATE=$(date +"%Y-%m-%d")

rm -rf triage.* build &

# Update the scripts, but revert repository back to last release for the
# first few builds.

hg pull
wait

[ -z "$FWL_STABLE" ] &&
  FWL_STABLE="$(hg tags | grep -v tip | head -n 1 | awk '{print $1}')"
hg update "$FWL_STABLE"

# Update each package from repository, generate alt-tarball, and build with
# that package.

for PACKAGE in busybox uClibc linux ""
do
  # Update package from repository

  export USE_UNSTABLE="$PACKAGE"
  if [ -z "$PACKAGE" ]
  then
    USE_UNSTABLE=busybox,uClibc,linux
    PACKAGE=all
    hg update tip
  else
    cd "$TOP/../$PACKAGE"
    echo pulling "$PACKAGE"
    git pull
    git archive master --prefix=$PACKAGE/ | bzip2 > \
      "$TOP"/packages/alt-$PACKAGE-0.tar.bz2
  fi

  # Build everything with unstable version of that package, and stable
  # version of everything else (including build scripts).

  cd "$TOP"
  FORK=1 CROSS_COMPILERS_EH=i686 NATIVE_COMPILERS_EH=1 nice -n 20 ./buildall.sh

  ./smoketest-all.sh --logs > build/status.txt

  DESTDIR="$TOP/../snapshots/$PACKAGE/$SNAPSHOT_DATE"
  rm -rf "$DESTDIR"
  mkdir -p "$DESTDIR"
  mv build/logs build/*.tar.bz2 "$DESTDIR"
  mv build triage.$PACKAGE
done

# Upload stuff

#scp -r ${SNAPSHOT_DIR} impact@impactlinux.com:/home/impact/impactlinux.com/fwl/downloads/snapshots/
