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
mkdir -p /var/log /usr/portage &&
cd /usr &&
#wget http://127.0.0.1/aboriginal/mirror/portage-latest.tar.bz2 -O - | \
wget http://gentoo.osuosl.org/snapshots/portage-latest.tar.bz2 -O - | \
  tar xjC /usr
if [ ! -d portage ]
then
  echo "Failed to download portage-latest tarball." >&2
  exit 1
fi

if ! emerge.real --sync
then
  echo "Sync failed"
  exit 1
fi

cd $(dirname $(readlink -f $(which emerge.real)))
mv emerge.real emerge

echo "Portage tree initialized"
