#!/bin/sh

# Run each of the individual package build files, in order.

[ -z "$MANIFEST" ] && MANIFEST=/usr/src/packages
touch "$MANIFEST"
  
[ -z "$FILTER" ] || FILTER="/$FILTER/d"
for i in $(sed -r -e "$FILTER" -e "s@#.*@@" /mnt/package-list)
do
  if [ -z "$FORCE" ] && grep -q "$i" "$MANIFEST"
  then
    echo "$i already installed"
    continue
  fi
  /mnt/build-one-package.sh "$i" || exit 1
  
  sed -i -e "/$i/d" "$MANIFEST" &&
  echo "$i" >> "$MANIFEST" || exit 1
done
