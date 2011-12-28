#!/bin/bash

# Setup alt-$PACKAGE-*.patch symlinks for a package

if [ $# -eq 0 ]
then
  echo "usage: more/alt-patches.sh PACKAGE"
  exit 1
fi

# Remove existing symlinks, but keep files

for i in sources/patches/alt-$1-*.patch
do
  [ -L $i ] && rm $i
done

for i in $(cd sources/patches; ls $1-*.patch)
do
  ln -s $i sources/patches/alt-$i
done
