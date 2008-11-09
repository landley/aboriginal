#!/bin/bash

# This is the cron script to create the nightly snapshots on
# "http://uclibc.org/~landley/fwl".  Unlike the other build scripts,
# this one runs as root so it can chroot to create static toolchains
# quickly.  (The nightly builds are done on an old, slow machine.)

# Set up context

WHOISIT=landley
HOSTARCH=i686
export USE_UNSTABLE=busybox,toybox,uClibc

#export UPLOAD_TO=busybox.net:public_html/fwlnew

cd /home/landley/firmware/firmware

# Zap old snapshots so fresh ones get downloaded from Morris, then
# download and extract packages.

rm -f sources/packages/alt-{uClibc,busybox}-0.tar.bz2
rm -rf build || exit 1
su ${WHOISIT} -c "./download.sh --extract && ./host-tools.sh" || exit 1

# Build a temporary system as a host architecture for static toolchains
su ${WHOISIT} -c "./cross-compiler.sh $HOSTARCH && ./mini-native.sh $HOSTARCH" || exit 1

# Chroot into the temporary system to build static uClibc toolchains

su ${WHOISIT} -c "hg archive build/mini-native-$HOSTARCH/build && cp -r sources/packages build/mini-native-$HOSTARCH/build/sources" || exit 1
(chroot build/mini-native-$HOSTARCH tools/bin/chroot-setup.sh || exit 1) << EOF
cd /build || exit 1
./download.sh --extract || exit 1
for i in \$(cd sources/targets; ls)
do
  BUILD_STATIC=1 ./cross-compiler.sh \$i 2>&1 | tee out-toolchain-\$i.txt
done
EOF

# Copy out static toolchains

rm -rf "build/cross-compiler-$HOSTARCH" || exit 1
mv build/mini-native-$HOSTARCH/build/build/cross-compiler-* build || exit 1

for i in $(cd build/mini-native-$HOSTARCH/build; ls out-*.txt)
do
  bzcat < build/mini-native-$HOSTARCH/build/"$i" > $i.bz2
done

rm -rf build/mini-native-* build/system-image-* || exit 1

# Build mini-native and system-image stages with static toolchains.

for i in $(cd sources/targets; ls)
do
  (./mini-native.sh $i && ./package-mini-native.sh $i) 2>&1 |
    tee >(bzip2 > out-$i.txt.bz2)
done

# Build system images using static toolchains above

# sources/build-all-targets.sh --stage 2 --fork 1 || exit 1

# Publish the result
#ssh -i /home/landley/.ssh/id_dsa ${WHOISIT}@${SERVER} \
#	"rm public_html/fwl/*; mv public_html/fwlnew/* public_html/fwl"
