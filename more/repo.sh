#!/bin/bash

# Populate a few source control directories. If they exist, they'll be used
# instead of source tarballs. (Note: if you want to apply patches you'll have
# to do it yourself, sources/patches only applies to tarballs.)

mkdir -p packages &&
if [ ! -d packages/busybox ]
then
  git clone git://busybox.net/busybox packages/busybox || exit 1
else
  (cd packages/busybox && git pull) || exit 1
fi

if [ ! -d packages/uClibc ]
then
  git clone git://uclibc.org/uClibc packages/uClibc
else
  (cd packages/uClibc && git pull) || exit 1
fi

if [ ! -d packages/linux ]
then
  git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux-2.6 \
    packages/linux || exit 1
else
  (cd packages/linux && git pull) || exit 1
fi

if [ ! -d packages/toybox ]
then
  hg clone http://landley.net/hg/toybox packages/toybox || exit 1
else
  (cd packages/toybox && hg pull -u) || exit 1
fi
