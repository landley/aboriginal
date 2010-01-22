#!/bin/bash

# Find the first breakage (since the last known good version) via git bisect.

if [ $# -ne 4 ]
then
  echo usage: bisectinate PACKAGE repodir@branch start arch >&2
  exit 1
fi

# Parse command line options

PKG="$1"
REPO="${2/@*/}"
BRANCH="${2/*@/}"
[ "$BRANCH" == "$2" ] && BRANCH=master
START="$3"
ARCH="$4"

FWLDIR="$(pwd)"

if [ ! -d "$REPO/.git" ]
then
  echo "No git repo at $REPO"
  exit 1
fi

# Start bisecting repository

mkdir -p build/logs
cd "$REPO" &&
git bisect reset &&
git bisect start &&
git bisect good "$START" || exit 1
RESULT="$(git bisect bad "$BRANCH")"
cd "$FWLDIR"

set -o pipefail

# Loop through bisection results

while true
do
  echo "$RESULT"

  # Are we done?

  [ ! "$(echo "$RESULT" | head -n 1 | grep "^Bisecting:")" ] && exit

  cd "$REPO"
  git show > "$FWLDIR/build/logs/test-${ARCH}.txt"
  git archive --prefix="$PKG/" HEAD | bzip2 \
    > "$FWLDIR/packages/alt-$PKG-0.tar.bz2" || exit 1
  cd "$FWLDIR"

  # Perform actual build

  RESULT=bad
  rm -rf build/*-"$ARCH"{,.tar.bz2} build/cron-temp/"$ARCH"-dropbearmulti
  EXTRACT_ALL=yes USE_UNSTABLE="$PKG" ./build.sh "$ARCH" \
    | tee -a build/logs/test-"$ARCH".txt
  if [ -e build/system-image-"$ARCH".tar.bz2 ]
  then
    if [ -z "$LONG" ]
    then
      RESULT=good
    else
     sources/more/native-static-build.sh "$ARCH" 2>&1 \
       | tee -a build/logs/test-"$ARCH".txt

      [ -e build/cron-temp/"$ARCH"-dropbearmulti ] && RESULT=good
    fi
  fi

  # If it built, try the native compile

  if [ "$RESULT" == "bad" ]
  then
    mv build/logs/{test,testfail}-"$ARCH".txt
  else
    rm build/logs/test-"$ARCH".txt
  fi

  cd "$REPO"
  RESULT="$(git bisect $RESULT)"
  cd "$FWLDIR"
done



#git bisect start
#git bisect good 57dded090d6
#git bisect bad origin/0_9_30
