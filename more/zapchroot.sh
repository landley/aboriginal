#!/bin/bash

# Copyright 2010 Rob Landley <rob@landley.net> licensed under GPLv2

if [ "$1" == "-d" ]
then
  DELETE=1
  shift
fi

# Clean up a chroot directory

ZAP=$(readlink -f "$1" 2>/dev/null)

if [ ! -d "$ZAP" ]
then
  echo "usage: zapchroot [-d] dirname"
  exit 1
fi

i="$(readlink -f "$(pwd)")"
if [ "$ZAP" == "${i:0:${#ZAP}}" ]
then
  echo "Sanity check failed: cwd is under zapdir" >&2
  exit 1
fi

# Iterate through the second entry of /proc/mounts in reverse order

for i in $(awk '{print $2}' /proc/mounts | tac)
do
  # De-escape octal versions of space, tab, backslash, newline...
  i=$(echo -e "$i")

  # Skip entries that aren't under our chroot
  [ "$ZAP" != "${i:0:${#ZAP}}" ] && continue

  echo "Umounting: $i"
  umount "$i"
done
