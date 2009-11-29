# Build and install uClibc++

setupfor uClibc++
CROSS= make defconfig &&
sed -r -i 's/(UCLIBCXX_HAS_(TLS|LONG_DOUBLE))=y/# \1 is not set/' .config &&
sed -r -i '/UCLIBCXX_RUNTIME_PREFIX=/s/".*"/""/' .config &&
CROSS= make oldconfig &&
CROSS="$ARCH"- make &&
CROSS= make install PREFIX="$ROOT_TOPDIR/c++" &&

# Move libraries somewhere useful.

mv "$ROOT_TOPDIR"/c++/lib/* "$ROOT_TOPDIR"/lib &&
rm -rf "$ROOT_TOPDIR"/c++/{lib,bin} &&
ln -s libuClibc++.so "$ROOT_TOPDIR"/lib/libstdc++.so &&
ln -s libuClibc++.a "$ROOT_TOPDIR"/lib/libstdc++.a

cleanup
