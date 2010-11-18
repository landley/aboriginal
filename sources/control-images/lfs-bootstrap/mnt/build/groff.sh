#!/bin/sh

PAGE=letter ./configure --prefix=/usr &&
make -j $CPUS &&
make docdir=/usr/share/doc/groff install &&
ln -s eqn /usr/bin/geqn &&
ln -s tbl /usr/bin/gtbl
