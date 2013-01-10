#!/bin/bash

# Run a native build with a control image for every architecture,
# using existing system-images under build, saving log files to build/log,
# uploading output into build.

# If $FORK is set, build them in parallel.

# Kill any build that doesn't produce output for $TIMEOUT (default 60) seconds.

. sources/utility_functions.sh || exit 1

if [ ! -f "$1" ]
then
  echo "Can't find control image at \"$1\"" >&2
  exit 1
fi

trap "killtree $$" EXIT

# Build the hdb images sequentially without timeout.sh, to avoid potential
# I/O storm triggering timeouts

[ ! -z "$FORK" ] && FORK= more/for-each-target.sh \
  '. sources/toys/make-hdb.sh; HDBMEGS=2048; HDB=build/system-image-$TARGET/hdb.img; echo "$HDB"; rm -f "$HDB"; make_hdb'

# Put each control image's output in the build directory

mkdir -p build/logs || dienow

# Run a control image for each target, using existing hdb.img

[ -z "$TIMEOUT" ] && export TIMEOUT=60
[ -z "$LOGFILE" ] && LOGFILE="$(echo $1 | sed 's@.*/\(.*\)\.hdc@\1@')"
more/for-each-target.sh \
  'ln -sfn .. build/system-image-$TARGET/upload && more/timeout.sh $TIMEOUT "HDB=hdb.img more/native-build-from-build.sh $TARGET '"$1 | tee build/logs/native-$LOGFILE-"'$TARGET.txt"'
