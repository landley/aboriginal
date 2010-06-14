#!/bin/bash

if [ "$1" != "--sync" ]
then
  echo 'No portage tree, run "emerge --sync".' >&2
  exit 1
fi

if [ "$(id -u)" -ne 0 ]
then
  echo "You are not root." >&2
  exit 1
fi

echo "Downloading portage tree..."
cd /usr
wget http://gentoo.osuosl.org/snapshots/portage-latest.tar.bz2 -O - | \
  tar xjC /usr/portage
if [ ! -d portage ]
then
  echo "Failed to download portage-latest tarball." >&2
  exit 1
fi

emerge.real --sync

cd $(dirname $(readlink -f $(which emerge.real)))
mv emerge.real emerge

echo "Portage tree initialized"
