#!/bin/bash

source include.sh

# I have no idea why this is spawning a subshell.  I want "thing || exit | tee"
# but there doesn't seem to be a syntax for that, so we remember PID and kill.

PARENT=$$
{
  ./download.sh || kill $PARENT
  ./host-tools.sh || kill $PARENT
} | tee out-all.txt

for i in "$@"
do
  {
    ./cross-compiler.sh "$i" || kill $PARENT
    ./mini-native.sh "$i" || kill $PARENT
  } | tee "out-$i.txt"
done
