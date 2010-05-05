#!/bin/bash

[ -z "$LFS" ] && LFS=/home/lfs
[ -z "$CPUS" ] && CPUS=1

SCRIPTPATH="$(which "$0")"

echo "LFS chapter 3: Download lfs-packages (grab one big tarball and extract)"

if [ ! -d "$LFS"/packages/. ]
then
  if [ ! -f "$LFS"/lfs-packages-6.3.tar ]
  then
    mkdir -p "$LFS" &&
    cd "$LFS" &&
    wget http://ftp.osuosl.org/pub/lfs/lfs-packages/lfs-packages-6.3.tar ||
    exit 1
  fi

  mkdir "$LFS"/packages &&
  cd "$LFS"/packages &&
  tar xvf ../lfs-packages-6.3.tar
fi

echo "LFS chapter 4.4: clear environment"

set +h
umask 022
export LC_ALL=POSIX
export PATH=/tools/bin:/bin:/usr/bin

# We can mostly use the FWL /tools tarball as the output of FWL chapter 5,
# except that glibc needs perl to build.  So add perl to /tools.

echo "LFS chapter 5.25: add perl to tools dir"

if [ ! -f /tools/bin/perl ]
then
  cd "$LFS" &&
  tar xvjf "$LFS"/packages/perl-*.tar.bz2 &&
  cd perl-5.*/ &&
  patch -p1 -i "$LFS"/packages/perl-*-libc-2.patch &&
  sed -i 's/libc\.so\.6/libc.so.0/g' hints/linux.sh &&
  ./configure.gnu --prefix=/tools -Dstatic_ext='Data/Dumper Fcntl IO POSIX' &&
  make -j $CPUS perl utilities &&
  PRIVLIB="$(sed -n 's/^privlib[\t ]*=[\t ]*//p' Makefile)" &&
  cp -v perl pod/pod2man /tools/bin &&
  mkdir -p "$PRIVLIB" &&
  cp -Rv lib/* "$PRIVLIB" &&
  cd .. &&
  rm -rf perl-5.*/

  [ $? -ne 0 ] && exit 1
fi

echo "LFS chapter 6.2: setup chroot (plus bind mount /tools into new subdir)."

if [ "$1" != "--no-chroot" ]
then
  mkdir -p "$LFS"/{dev,proc,sys,tools,root/work} &&
  ln -s /packages "$LFS"/root/work/packages &&
  mount --bind /tools "$LFS"/tools &&
  mount -vt proc proc "$LFS"/proc &&
  mount -vt sysfs sysfs "$LFS"/sys || exit 1

  # These are allowed to fail (may already exist if script is re-run), but
  # must happen before the /dev bind mount to give udev stuff to use.

  mknod -m 600 "$LFS"/dev/console c 5 1
  mknod -m 666 "$LFS"/dev/null c 1 3

  mount -v --bind /dev "$LFS"/dev || exit 1

  # These may fail if host's /dev doesn't have pts or shm subdirectories.

  mount -vt devpts devpts "$LFS"/dev/pts
  mount -vt tmpfs shm "$LFS"/dev/shm

  echo "LFS chapter 6.4: chroot (tweaked quite a bit)."

  # Perform the chroot, re-running this script with extra argument
  # (--no-chroot) and several more environment variables

  cp "$SCRIPTPATH" "$LFS"/mklfs.sh &&
  chroot "$LFS" /tools/bin/env -i \
    HOME=/root TERM="$TERM" PS1='\u:\w\$ ' \
    PATH=/bin:/usr/bin:/sbin:/usr/sbin:/tools/bin \
    UCLIBC_DYNAMIC_LINKER=/tools/lib/ld-uClibc.so.0 \
    UCLIBC_RPATH=/tools/lib LFS="/root/work" CPUS=$CPUS \
    /tools/bin/bash /mklfs.sh --no-chroot

  # The chroot exited.  Snapshot return code, clean up mounts, return.

  RETVAL=$?
  umount "$LFS"/{dev/{pts,shm},proc,sys,tools}
  umount "$LFS"/dev
  exit $RETVAL
fi

# At this point, we've either done the chroot already or we're not doing one.

echo "LFS chapter 6.5: creating directories"

mkdir -p /{bin,boot,etc/opt,home,lib,mnt,opt} &&
mkdir -p /{media/{floppy,cdrom},sbin,srv,var} &&
install -dv -m 0750 /root &&
install -dv -m 1777 /tmp /var/tmp &&
mkdir -p /usr/{,local/}{bin,include,lib,sbin,src} &&
mkdir -p /usr/{,local/}share/{doc,info,locale,man} &&
mkdir /usr/{,local/}share/{misc,terminfo,zoneinfo} &&
mkdir -p /usr/{,local/}share/man/man{1..8} || exit 1
for dir in /usr /usr/local; do
  ln -s share/{man,doc,info} $dir || exit 1
done
mkdir /var/{lock,log,mail,run,spool} &&
mkdir -p /var/{opt,cache,lib/{misc,locate},local} || exit 1

echo "LFS chapter 6.6: symlinks pointing into /tools and general bootstrapping"

# Note: /etc/mtab is dead, so no touch: symlink /etc/mtab to /proc/mounts

ln -s /tools/bin/{bash,cat,echo,grep,pwd,stty} /bin &&
ln -s /tools/bin/perl /usr/bin &&
ln -s /tools/lib/libgcc_s.so{,.1} /usr/lib &&
ln -s /tools/lib/libstdc++.so{,.6} /usr/lib &&
ln -s bash /bin/sh &&
ln -s /proc/mounts /etc/mtab &&

cat > /etc/passwd << "EOF" &&
root:x:0:0:root:/root:/bin/bash
nobody:x:99:99:Unprivileged User:/dev/null:/bin/false
EOF

cat > /etc/group << "EOF" &&
root:x:0:
bin:x:1:
sys:x:2:
kmem:x:3:
tty:x:4:
tape:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
usb:x:14:
cdrom:x:15:
mail:x:34:
nogroup:x:99:
EOF

touch /var/run/utmp /var/log/{btmp,lastlog,wtmp} &&
chgrp utmp /var/run/utmp /var/log/lastlog &&
chmod 664 /var/run/utmp /var/log/lastlog ||
exit 1

echo "LFS chapter 6.7: kernel API headers"

cd "$LFS" &&
tar xvjf "$LFS"/packages/linux-*.tar.bz2 &&
cd linux-* &&
sed -i '/scsi/d' include/Kbuild &&
make -j $CPUS INSTALL_HDR_PATH=/usr headers_install &&
cd .. &&
rm -rf linux-* ||
exit 1

echo "LFS 6.8: man pages"

cd "$LFS" &&
tar xvjf "$LFS"/packages/man-pages-*.tar.bz2 &&
cd man-pages-* &&
make -j $CPUS install &&
cd .. &&
rm -rf man-pages-* ||
exit 1

echo "LFS 6.9: glibc"

cd "$LFS" &&
tar xvjf "$LFS"/packages/glibc-[0-9]*.tar.bz2 &&
cd glibc-* &&
tar xvzf "$LFS"/packages/glibc-libidn-*.tar.gz &&
mv glibc-libidn-* libidn &&
sed -i '/vi_VN.TCVN/d' localedata/SUPPORTED &&
sed -i \
's|libs -o|libs -L/usr/lib -Wl,-dynamic-linker=/lib/ld-linux.so.2 -o|' \
        scripts/test-installation.pl &&
sed -i 's|@BASH@|/bin/bash|' elf/ldd.bash.in &&
mkdir ../glibc-build &&
cd ../glibc-build &&
../glibc-2.5.1/configure --prefix=/usr \
    --disable-profile --enable-add-ons \
    --enable-kernel=2.6.0 --libexecdir=/usr/lib/glibc &&
make -j $CPUS

/tools/bin/ash
