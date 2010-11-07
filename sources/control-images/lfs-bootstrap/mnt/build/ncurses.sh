#!/bin/sh

[ ! -z "$(which c++)" ] && X="--without-cxx --without-cxx-binding"

./configure --prefix=/usr --with-shared --without-debug --enable-widec $X &&
make -j $CPUS &&
make install || exit 1

# Make sure various packages can find ncurses no matter what weird names
# they look for.

for lib in ncurses form panel menu
do
    ln -sf lib${lib}w.so /usr/lib/lib${lib}.so &&
    ln -sf lib${lib}w.a /usr/lib/lib${lib}.a || exit 1
done
ln -sf libncursesw.so libcursesw.so &&
ln -sf libncurses.so /usr/lib/libcurses.so &&
ln -sf libncursesw.a /usr/lib/libcursesw.a &&
ln -sf libncurses.a /usr/lib/libcurses.a || exit 1

if [ ! -z "$(which c++)" ]
then
  ln -sf libncurses++w.a /usr/lib/libncurses++.a || exit 1
fi
