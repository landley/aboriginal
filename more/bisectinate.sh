#!/bin/bash

# Development script: bisect a git repository to find the first broken commit
# since the last known good version.

# If any of the pipe segments fail, treat that as a fail.

set -o pipefail

if [ $# -lt 4 ]
then
  echo "usage: bisectinate ARCH PACKAGE REPO[@BAD] GOOD [TEST...]" >&2
  echo >&2
  echo "Bisect PACKAGE for ARCH, from START to BAD within REPO" >&2
  exit 1
fi

# Parse command line options

ARCH="$1"
PKG="$2"
REPO="${3/@*/}"
BRANCH="${3/*@/}"
[ "$BRANCH" == "$3" ] && BRANCH=master
START="$4"
shift 4
TEST="$1"

TOP="$(pwd)"
[ -z "$SRCDIR" ] && SRCDIR="$TOP/packages"
[ -z "$BUILD" ] && BUILD="$TOP/build"

if [ ! -d "$REPO/.git" ]
then
  echo "No git repo at $REPO"
  exit 1
fi

[ -z "$TEST" ] && TEST=true

# For kernel and busybox bisects, only redo part of the build

if [ "$PKG" == linux ] && [ -e "$BUILD/root-filesystem-$ARCH".tar.bz2 ]
then
  ZAPJUST=linux-kernel
elif [ "$PKG" == busybox ] &&
     [ -e "$BUILD/simple-cross-compiler-$ARCH.tar.bz2" ]
then
  ZAPJUST=root-filesystem
else
  ZAPJUST=
fi

# Initialize bisection repository

rm -rf "$BUILD/packages/alt-$PKG" "$SRCDIR/alt-$PKG-0.tar.bz2" &&
mkdir -p "$BUILD"/{logs,packages} &&
cd "$BUILD/packages" &&
git clone "$REPO" "alt-$PKG" &&
cd "alt-$PKG" &&
git bisect start &&
git bisect good "$START" || exit 1

RESULT="bad $BRANCH"

# Loop through bisection results

while true
do
  # Bisect repository to prepare next version to build.  Exit if done.

  cd "$BUILD/packages/alt-$PKG" &&
  git clean -fdx &&
  git checkout -f || exit 1

  RESULT="$(git bisect $RESULT)"
  echo "$RESULT"
  [ ! "$(echo "$RESULT" | head -n 1 | grep "^Bisecting:")" ] && exit

  # Update log

  git show > "$BUILD/logs/bisectinate-${ARCH}.txt"
  git bisect log > "$BUILD/logs/bisectinate-${ARCH}.log"
  # The "cat" bypasses git's stupid overengineered built-in call to less.
  git log HEAD -1 | cat
  echo "Testing..."

  cd "$TOP" || exit 1

  # Figure out how much ./build.sh needs to rebuild

  [ ! -z "$ZAPJUST" ] &&
    rm -rf "$BUILD/${ZAPJUST}-$ARCH"{,.tar.bz2} ||
    rm -rf "$BUILD"/*-"$ARCH"{,.tar.bz2}

  # Try the build

  EXTRACT_ALL=1 ALLOW_PATCH_FAILURE=1 USE_ALT="$PKG" \
    ./build.sh "$ARCH" 2>&1 | tee -a "$BUILD"/logs/bisectinate-"$ARCH".txt

  # Did it work?

  RESULT=bad
  if [ -e "$BUILD"/system-image-"$ARCH".tar.bz2 ]
  then
    set -o pipefail
    ARCH="$ARCH" more/timeout.sh 60 "$TEST" 2>&1 | \
      tee -a "$BUILD/logs/bisectinate-$ARCH".txt
    [ $? -eq 0 ] && RESULT=good
  fi

  # Keep the last "good" and "bad" logs, separately.

  mv "$BUILD"/logs/bisectinate{,-$RESULT}-"$ARCH".txt
done
