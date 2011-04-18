#!/bin/bash

# Build stable versions of all packages with current scripts.

# This gets run in the aboriginal top directory.

pull_repo()
{
  # Clone working copy

  rm -rf "packages/alt-$1-0.tar.bz2" build/packages/alt-$1
  mkdir -p build/packages/alt-$1
  pushd build/packages/alt-$1 &&
  ln -s ../../../repos/$1/.git .git &&
  git checkout -f master &&
  git pull
  popd
}

# Expire snapshots directory

SNAPSHOTS="$(find snapshots -mindepth 1 -maxdepth 1 -type d)"
COUNT=$(( $(echo "$SNAPSHOTS" | wc -l) - 30 ))
if [ "$COUNT" -gt 0 ]
then
  # Delete appropriate number of oldest entries, then dead symlinks.
  rm -rf $( echo "$SNAPSHOTS" | sort | head -n $COUNT )
  rm -rf $(find -L snapshots -type l)
fi

echo === Begin cron job

# Start a new snapshot

export SNAPSHOT_DATE=$(date +"%Y-%m-%d")
mkdir -p snapshots/$SNAPSHOT_DATE/base &&
rm snapshots/latest &&
ln -sf $SNAPSHOT_DATE snapshots/latest || exit 1

# build base repo

export FORK=1
export CROSS_COMPILER_HOST=i686
hg pull -u

build_snapshot()
{
  if [ -z "$USE_UNSTABLE" ]
  then
    SNAPNAME=base
  else
    pull_repo $USE_UNSTABLE
    SNAPNAME=$USE_UNSTABLE
  fi

  echo === Building snapshot $SNAPNAME

  [ "$USE_UNSTABLE" == linux ] &&
    more/for-each-arch.sh 'more/migrate-kernel.sh $TARGET'

  # Update manifest

  ./download.sh

  # If it's unchanged, just hardlink the previous binaries instead of rebuilding

  if cmp -s snapshots/latest/$SNAPNAME/MANIFEST packages/MANIFEST
  then
    cp -rl snapshots/latest/$SNAPNAME/* snapshots/$SNAPSHOT_DATE/$SNAPNAME
    return
  fi

  # Build it

  nice -n 20 more/buildall.sh
  rm build/simple-cross-compiler-*.tar.bz2
  mv build/*.tar.bz2 build/logs build/MANIFEST snapshots/$SNAPSHOT_DATE/$SNAPNAME
}

build_snapshot base

echo === Building QEMU

# build qemu-git

QPATH=""
CPUS=$(echo /sys/devices/system/cpu/cpu[0-9]* | wc -w)
pull_repo qemu
pushd build/packages/alt-qemu
./configure --disable-werror &&
nice -n 20 make -j $CPUS 2>&1 | tee build/logs/alt-qemu.txt &&
QPATH="$(for i in *-softmmu;do echo -n $(pwd)/$i:; done)"
popd

# test all with qemu-git

[ -z "$QPATH" ] ||
  PATH="$QPATH:$PATH" more/for-each-target.sh \
    'more/smoketest.sh $TARGET | tee snapshots/$SNAPSHOT_DATE/base/logs/newqemu-smoketest-$TARGET.txt'

#USE_UNSTABLE=linux build_snapshot
#USE_UNSTABLE=uClibc build_snapshot
#USE_UNSTABLE=busybox build_snapshot
