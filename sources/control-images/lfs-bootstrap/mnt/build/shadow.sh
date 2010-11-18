#!/bin/sh

# Disable the groups program, coreutils provides a better one.

sed -i 's/groups$(EXEEXT) //' src/Makefile.in &&
find man -name Makefile.in -exec sed -i 's/groups\.1 / /' {} \; &&

# Disable Chinese/Korean man pages Man-DB can't format properly.

sed -i -e 's/ ko//' -e 's/ zh_CN zh_TW//' man/Makefile.in &&

# Change default password encryption to something that _doesn't_ limit
# password lengths to 8 characters, and change the user mbox location to
# the "new" one everybody started using back in the 1990's.

sed -i -e 's@#ENCRYPT_METHOD DES@ENCRYPT_METHOD MD5@' \
       -e 's@/var/spool/mail@/var/mail@' etc/login.defs &&
       
./configure --sysconfdir=/etc &&
make -j $CPUS &&
make install &&
pwconv &&
grpconv
