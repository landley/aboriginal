#!/bin/sh

# Run each of the individual package build files, in order.

for i in zlib ncurses python bash rsync patch file portage
do
  cd /home && /mnt/${i}-build || exit 1
done
