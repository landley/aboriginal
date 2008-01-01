#!/bin/bash

# Test script to build every target architecture, logging output.
#  With --fork, it builds them in parallel
#  With --nofork, it build them sequentially
#  With --watch, it displays output from an existing parallel build

function buildarch()
{
  nice -n 20 ./cross-compiler.sh $1 &&
  nice -n 20 ./mini-native.sh $1 &&
  nice -n 20 ./package-mini-native.sh $1
}

if [ "$1" != "--watch" ]
then
  if [ $# -ne 0 ]
  then
    (nice -n 20 ./download.sh &&
     nice -n 20 ./host-tools.sh &&
     nice -n 20 ./download.sh --extract ) || exit 1
  fi
  for i in `cd sources/configs; ls`
  do
    if [ "$1" == "--nofork" ]
    then
      buildarch $i 2>&1 | tee out-$i.txt || exit 1
    elif [ "$1" == "--fork" ]
    then
      (buildarch $i > out-$i.txt 2>&1 &)&
    else
      echo "Usage: forkbomb.sh [--fork] [--nofork] [--watch]"
      exit 1
    fi
  done
fi
watch -n 3 'X=; for i in *.txt; do /bin/echo -e "$X$i"; X="\n"; tail -n 1 $i; done'
