#!/bin/sh

if [ ! -e /etc/hosts ]
then
  echo "127.0.0.1 localhost $(hostname)" > /etc/hosts || exit 1
fi

# Configure hardwires on the "stack protector", which doesn't work in this
# context.  Rip out all mention of it.

sed -i 's/-fstack-protector//' Configure &&

# Make Perl use the system zlib instead of a built-in copy.

sed -i -e "s|BUILD_ZLIB\s*= True|BUILD_ZLIB = False|"           \
       -e "s|INCLUDE\s*= ./zlib-src|INCLUDE    = /usr/include|" \
       -e "s|LIB\s*= ./zlib-src|LIB        = /usr/lib|"         \
    cpan/Compress-Raw-Zlib/config.in &&
./Configure -des -Dprefix=/usr -Dvendorprefix=/usr \
  -Dman1dir=/usr/share/man/man1 -Dman3dir=/usr/share/man/man3 \
  -Dpager="/usr/bin/less -is" -Duseshrplib -Dusenm=n &&
make -j $CPUS || exit 1

if [ ! -z "$CHECK" ]
then
  make test || exit 1
fi

make install
