#!/bin/bash

# Run smoketest script on every build/system-image-* architecture.

# If $FORK is set, run them in parallel.

[ -z "$FORK" ] || TIMEOUT=${TIMEOUT:-180}

. sources/utility_functions.sh || exit 1

function dotest()
{
  [ -z "$FORK" ] && echo -n "Testing $1:"
  [ ! -z "$VERBOSE" ] && VERBOSITY="tee >(cat >&2) |"
  RESULT="$(more/smoketest.sh "$1" 2>&1 | eval "$VERBOSITY grep 'Hello world!'")"
  [ -z "$RESULT" ] && RESULT="FAIL" || RESULT="PASS"
  [ -z "$FORK" ] && echo "$RESULT" || echo "Testing $1:$RESULT"
  rm -f build/system-image-"$1"/hdb.img 2>/dev/null
}

# Test all non-hw targets to see whether or not they can compile and run
# the included "hello world" program.

for i in $(ls -d sources/targets/* | sed 's@.*/@@' | grep -v "^hw-")
do
  if [ -e "build/system-image-$i" ]
  then
    maybe_fork "dotest $i"
  else
    echo "Testing $i:NONE"
  fi
done

wait
