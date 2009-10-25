#!/bin/bash

# Run smoketest script on every build/system-image-* architecture.

# If $FORK is set, run them in parallel.

. sources/functions.sh || exit 1

if [ "$1" == "--logs" ]
then
  for i in build/logs/smoketest-*.txt
  do
    NAME="$(echo $i | sed 's/.*smoketest-\(.*\)\.txt/\1/')"
    echo -n "Testing $NAME:"
    RESULT="$(grep 'Hello world!' "$i")"
    [ -z "$RESULT" ] && echo "FAIL" || echo "PASS"
  done

  exit
fi

function dotest()
{
  [ -z "$FORK" ] && echo -n "Testing $1:"
  [ ! -z "$VERBOSE" ] && VERBOSITY="tee >(cat >&2) |"
  RESULT="$(./smoketest.sh "$1" 2>&1 | eval "$VERBOSITY grep 'Hello world!'")"
  [ -z "$RESULT" ] && RESULT="FAIL" || RESULT="PASS"
  [ -z "$FORK" ] && echo "$RESULT" || echo "Testing $1:$RESULT"
  rm -f build/system-image-"$1"/hdb.img 2>/dev/null
}

# Test all non-hw targets to see whether or not they can compile and run
# the included "hello world" program.

for i in $(ls -pd build/system-image-* | sed -n 's@.*/system-image-\(.*\)/@\1@p' | grep -v "^hw-")
do
  maybe_fork "dotest $i"
done

wait
