#!/bin/bash

# Create an ext2 root filesystem image

source include.sh

#echo -n "Creating tools.sqf"
#("${WORK}/mksquashfs" "${NATIVE}/tools" "${WORK}/tools.sqf" \
#  -noappend -all-root -info || dienow) | dotprogress

# A 256 meg sparse image
rm -f "$IMAGE"
dd if=/dev/zero of="$IMAGE" bs=1024 seek=$[2048*1024-1] count=1 &&
/sbin/mke2fs -b 1024 -F "$IMAGE" &&

# User User Mode Linux to package this, until toybox mke2fs is ready.

# Write out a script to control user mode linux
cat > "${WORK}/uml-package.sh" << EOF &&
#!/bin/sh
mount -n -t ramfs /dev /dev
mknod /dev/loop0 b 7 1
# Jump to build dir
echo copying files...
cd "$BUILD"
/sbin/losetup /dev/loop0 "$IMAGE"
mount -n -t ext2 /dev/loop0 "$WORK"
tar cC "$NATIVE" tools | tar xC "$WORK"
mkdir "$WORK"/dev
mknod "$WORK"/dev/console c 5 1
umount "$WORK"
/sbin/losetup -d /dev/loop0
umount /dev
sync
EOF
chmod +x ${WORK}/uml-package.sh &&
linux rootfstype=hostfs rw quiet ARCH=${ARCH} PATH=${PATH} init="${HOSTTOOLS}/oneit -p ${WORK}/uml-package.sh"


