#!/bin/sh

# Another bugfix that you'd think would be a patch, but no...

sed -i 's@#include<sys\/usr.h>@#include <bits\/types.h>\&@' configure &&

./configure --prefix=/usr &&
make -j $CPUS &&
make install
