#!/bin/bash

if [ ! -d "$1" ]
then
  echo "usage: gen_initramfs_list.sh dirname" >&2
  exit 1
fi

LEN=$(echo $1 | wc -c)

find "$1" | while read i
do
  PERM=$(stat -c %a "$i")
  NAME="$(echo $i | cut -b ${LEN}-)"

  [ -z "$NAME" ] && continue

  if [ -L "$i" ]
  then
      echo "slink $NAME $(readlink "$i") $PERM 0 0"
  elif [ -f "$i" ]
  then
      echo "file $NAME $i $PERM 0 0"
  elif [ -d "$i" ]
  then
      echo "dir $NAME $PERM 0 0"
  fi
done
