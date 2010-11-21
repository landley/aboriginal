#!/bin/sh

# arpd needs berkeley DB, switch it off.
sed -i '/^TARGETS/s@arpd@@g' misc/Makefile &&

# bugfix, why this isn't a patch I have no idea.
sed -i '1289i\\tfilter.cloned = 2;' ip/iproute.c &&

# Don't be confused by symlinks
sed -i 's/ find / find -L /g' Makefile &&

make DESTDIR= -j $CPUS &&
make DESTDIR= SBINDIR=/sbin MANDIR=/usr/share/man \
  DOCDIR=/usr/share/doc/iproute2 install
