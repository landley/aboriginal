#!/bin/sh

# Stub to compile packages that refuse to build without gettext.

gcc -shared -fpic -o /usr/lib/libintl.so libintl-stub.c &&
cp libintl-stub.h /usr/include/libintl.h &&
cp msgfmt /usr/bin
