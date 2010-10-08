#!/bin/sh

# Run each of the individual package build files, in order.

for i in zlib ncurses python bash rsync patch file portage
do
  /mnt/build-one-package.sh "$i" || exit 1
done
