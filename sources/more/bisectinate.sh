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

TOP="$(pwd)"
[ -z "$SRCDIR" ] && SRCDIR="$TOP/packages"
[ -z "$BUILD" ] && BUILD="$TOP/build"

if [ ! -d "$REPO/.git" ]
then
  echo "No git repo at $REPO"
  exit 1
fi

# For kernel and busybox bisects, only redo part of the build

if [ "$PKG" == linux ] && [ -e "$BUILD/root-filesystem-$ARCH".tar.bz2 ]
then
  ZAPJUST=system-image
elif [ "$PKG" == busybox ] &&
     [ -e "$BUILD/simple-cross-compiler-$ARCH.tar.bz2" ]
then
  ZAPJUST=root-filesystem
else
  ZAPJUST=
fi

# Start bisecting repository

mkdir -p "$BUILD"/logs
cd "$REPO" &&
git clean -fdx && git checkout -f &&
git bisect reset &&
git bisect start &&
git bisect good "$START" || exit 1
RESULT="$(git bisect bad "$BRANCH")"
cd "$TOP"

set -o pipefail

# Loop through bisection results

while true
do
  echo "$RESULT"

  # Are we done?

  [ ! "$(echo "$RESULT" | head -n 1 | grep "^Bisecting:")" ] && exit

  cd "$REPO"
  git show > "$BUILD/logs/test-${ARCH}.txt"
  # The "cat" bypasses git's stupid overengineered built-in call to less.
  git log HEAD -1 | cat
  echo "Testing..."
  git archive --prefix="$PKG/" HEAD | bzip2 \
    > "$SRCDIR/alt-$PKG-0.tar.bz2" || exit 1
  cd "$TOP"

  # Perform actual build

  RESULT=bad

  [ ! -z "$ZAPJUST" ] &&
    rm -rf "$BUILD/${ZAPJUST}-$ARCH"{,.tar.bz2} ||
    rm -rf "$BUILD"/*-"$ARCH"{,.tar.bz2}
  EXTRACT_ALL=yes USE_UNSTABLE="$PKG" ./build.sh "$ARCH" \
    | tee -a "$BUILD"/logs/test-"$ARCH".txt
  if [ -e "$BUILD"/system-image-"$ARCH".tar.bz2 ]
  then
    if [ -z "$LONG" ]
    then
      RESULT=good
    else
     rm -rf "$BUILD"/cron-temp/"$ARCH"-dropbearmulti
     sources/more/native-static-build.sh "$ARCH" 2>&1 \
       | tee -a "$BUILD"/logs/test-"$ARCH".txt

      [ -e "$BUILD"/cron-temp/"$ARCH"-dropbearmulti ] && RESULT=good
    fi
  fi

  # If it built, try the native compile

  if [ "$RESULT" == "bad" ]
  then
    mv "$BUILD"/logs/{test,testfail}-"$ARCH".txt
  else
    rm "$BUILD"/logs/test-"$ARCH".txt
  fi

  cd "$REPO"
  RESULT="$(git bisect $RESULT)"
  cd "$TOP"
done
