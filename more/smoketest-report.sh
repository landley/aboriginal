#!/bin/bash

. sources/utility_functions.sh || exit 1

# Test all architctures to see whether or not they can compile and run
# the included "hello world" program.

echo "Architecture,Smoketest,Control Image,Build Stage"

for i in $(ls sources/targets | sed 's@.*/@@')
do
  [ ! -f "sources/targets/$i" ] && continue

  echo -n "$i,"

  grep -q 'Hello world!' build/logs/smoketest-$i.txt 2>/dev/null &&
    echo -n "PASS," || echo -n "FAIL,"

  [ -e "build/native-static/dropbearmulti-$i" ] &&
    echo -n "PASS," || echo -n "FAIL,"

  echo $(
    sed -n 's/^=== \([^(]*\)([^ ]* \(.*\))/\2 \1/p' \
      build/logs/build-$i.txt | tail -n 1 )
done
