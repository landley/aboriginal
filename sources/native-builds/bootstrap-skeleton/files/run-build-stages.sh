#!/bin/sh

# Run each of the individual package build files, in order.

[ -z "$FILTER" ] || FILTER="/$FILTER/d"
for i in $(sed -r -e "$FILTER" -e "s@#.*@@" /mnt/package-list)
do
  /mnt/build-one-package.sh "$i" || exit 1
done
