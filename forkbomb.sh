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
     # host-tools populates one directory with every command the build needs,
     # so we can ditch the old $PATH afterwards.
     nice -n 20 ./host-tools.sh &&
     PATH=`pwd`/build/host &&
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

if [ "$1" != "--nofork" ]
then
  watch -n 3 'X=; for i in out-*.txt; do /bin/echo -e "$X$i"; X="\n"; tail -n 1 $i; done'
fi
