#!/bin/sh

# Portage isn't really designed to be portable, so this script contains
# the "make install" stage that portage really should have within itself.

# Install portage user/group, and libraries.

echo portage:x:250:250:portage:/var/tmp/portage:/bin/false >> /etc/passwd &&
echo portage::250:portage >> /etc/group &&
mkdir -p /usr/lib/portage &&
cp -a bin pym /usr/lib/portage/ &&

# Add portage python modules to the python search path.

echo /usr/lib/portage/pym > /usr/lib/python2.6/site-packages/gentoo.pth ||
  exit 1

# Install portage binaries into bin and sbin

for i in archive-conf dispatch-conf emaint emerge-webrsync env-update \
         etc-update fixpackages quickpkg regenworld
do
  ln /usr/lib/portage/bin/$i /usr/sbin/$i || exit 1
done

for i in  ebuild egencache emerge portageq repoman
do
  ln /usr/lib/portage/bin/$i /usr/bin/$i || exit 1
done

# Install portage man pages

cp cnf/make.globals /etc/ &&
cp man/*.1 /usr/man/man1 &&
cp man/*.5 /usr/man/man5 &&

mkdir -p /var/log /etc/portage/profile
