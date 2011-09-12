#!/bin/bash

# Natively build for every target architecture, saving log files to build/log.
# If $FORK is set, build them in parallel.

. sources/utility_functions.sh || exit 1

if [ ! -f "$1" ]
then
  echo "Can't find control image at \"$1\"" >&2
  exit 1
fi

trap "killtree $$" EXIT

# Build the hdb images sequentially without timeout.sh, to avoid potential
# I/O storm triggering timeouts

FORK= more/for-each-target.sh \
  '. sources/toys/make-hdb.sh; HDBMEGS=2048; HDB=build/system-image-$TARGET/hdb.img; echo "$HDB"; rm -f "$HDB"; make_hdb'

# Build static-tools (dropbear and strace) for each target

mkdir -p build/native-static || dienow
more/for-each-target.sh \
  'ln -sf ../native-static build/system-image-$TARGET/upload'

[ -z "$TIMEOUT" ] && export TIMEOUT=60
more/for-each-target.sh \
  'more/timeout.sh $TIMEOUT "HDB=hdb.img more/native-build-from-build.sh $TARGET "'"$1"'" | tee build/logs/native-$TARGET.txt"'
