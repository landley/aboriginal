#!/bin/sh

# Swap out incestuous knowledge of the internals of glibc for incestuous
# knowledge of the internals of uClibc.  (Should never trigger anyway.)

sed -i 's/thread_locale->__names\[category]/thread_locale->cur_locale/' \
  gettext-runtime/intl/localename.c gettext-tools/gnulib-lib/localename.c &&
sed -i 's%LIBS = @LIBS@%LIBS = @LIBS@ ../libgrep/libgrep.a%' \
  gettext-tools/src/Makefile.in gettext-tools/tests/Makefile.in &&

./configure --prefix=/usr --docdir=/usr/share/doc/gettext &&
make -j $CPUS || exit 1

if [ ! -z "$DOCS" ]
then
  make check || exit 1
fi

make install
