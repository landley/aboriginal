#!/tools/bin/sh

# If you're doing a Linux From Scratch build, the /tools directory is
# sufficient.  (Start by installing kernel headers and building a C library.)

# Otherwise, building source packages wants things like /bin/bash and
# running the results wants /lib/ld-uClibc.so.0, so set up some directories
# and symlinks to let you easily compile source packages.

# Add /tools to $PATH if it's not there

if [ -d tools/bin ] && [ -z "$(echo :$PATH | tools/bin/grep :/tools/bin)" ]
then
  [ -z "$PATH" ] && PATH=/tools/bin || PATH="$PATH":/tools/bin
  export PATH
fi
export HOME=/home

# Create some temporary directories at the root level
mkdir -p  proc sys dev etc tmp home
[ ! -e bin ] && ln -s tools/bin bin
[ ! -e lib ] && ln -s tools/lib lib
[ ! -e usr ] && ln -s tools usr

# Populate /dev
mountpoint -q sys || mount -t sysfs sys sys
mountpoint -q dev || mount -t tmpfs -o noatime dev dev
mdev -s

# Mount /proc is there
mountpoint -q proc || mount -t proc proc proc

# If we're running under qemu, do some more setup
if [ $$ -eq 1 ]
then

  # Note that 10.0.2.2 forwards to 127.0.0.1 on the host.

  # Setup networking for QEMU (needs /proc)
  ifconfig eth0 10.0.2.15
  route add default gw 10.0.2.2

  # If we have no RTC, try rdate instead:
  [ `date +%s` -lt 1000 ] && rdate 10.0.2.2 # or time-b.nist.gov

  # If there's a /dev/hdb or /dev/sdb, mount it on home

  [ -b /dev/hdb ] && HOMEDEV=/dev/hdb
  [ -b /dev/sdb ] && HOMEDEV=/dev/sdb
  if [ ! -z "$HOMEDEV" ]
  then
    mount -o noatime $HOMEDEV /home
  fi

  mount -o noatime -t tmpfs /tmp /tmp

  echo Type exit when done.
  exec /tools/bin/oneit -c /dev/"$(dmesg | sed -n '/^Kernel command line:/s@.* console=\(/dev/\)*\([^ ]*\).*@\2@p')" /tools/bin/ash

# If we're not PID 1, it's probably a chroot.
else
  echo "nameserver 4.2.2.1" > /etc/resolv.conf

  # Switch to a shell with command history.

  echo Type exit when done.
  /tools/bin/ash
  cd /
  umount ./dev
  umount ./home
  umount ./sys
  umount ./proc
  sync
fi
