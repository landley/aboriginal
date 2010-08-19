#!/bin/sh

# Otherwise, building source packages wants things like /bin/bash and
# running the results wants /lib/ld-uClibc.so.0, so set up some directories
# and symlinks to let you easily compile source packages.

export HOME=/home

# Populate /dev
mountpoint -q sys || mount -t sysfs sys sys
mountpoint -q dev || mount -t tmpfs -o noatime dev dev
mdev -s

# Make sure /proc is there
mountpoint -q proc || mount -t proc proc proc

[ -z "$CPUS" ] && export CPUS=1
export PS1='($HOST:$CPUS) \w \$ '

# If we're running under qemu, do some more setup
if [ $$ -eq 1 ]
then

  # Note that 10.0.2.2 forwards to 127.0.0.1 on the host.

  # Setup networking for QEMU (needs /proc)
  ifconfig eth0 10.0.2.15
  route add default gw 10.0.2.2

  # If we have no RTC, try rdate instead:
  [ "$(date +%s)" -lt 1000 ] && rdate 10.0.2.2 # or time-b.nist.gov

  mount -t tmpfs /tmp /tmp

  # If there's a /dev/hdb or /dev/sdb, mount it on home

  [ -b /dev/hdb ] && HOMEDEV=/dev/hdb
  [ -b /dev/sdb ] && HOMEDEV=/dev/sdb
  if [ ! -z "$HOMEDEV" ]
  then
    mount -o noatime $HOMEDEV /home
  else
    # Only mount a tmpfs if / isn't writeable.
    touch /.temp 2>/dev/null
    [ $? -ne 0 ] && mount -t tmpfs /home /home || rm /.temp
  fi
  cd /home

  [ -b /dev/hdc ] && MNTDEV=/dev/hdc
  [ -b /dev/sdc ] && MNTDEV=/dev/sdc
  if [ ! -z "$MNTDEV" ]
  then
    mount -o ro $MNTDEV /mnt
  fi

  CONSOLE="$(sed -n 's@.* console=\(/dev/\)*\([^ ]*\).*@\2@p' /proc/cmdline)"
  [ -z "$CONSOLE" ] && CONSOLE=/dev/console

  if [ -z "$DISTCC_HOSTS" ]
  then
    echo "Not using distcc."
  else
    echo "Distcc acceleration enabled."
  fi
  echo Type exit when done.

  HANDOFF=/bin/ash
  if [ -e /mnt/init ]
  then
    X=xx
    echo "Press any key for command line..."
    read -t 3 -n 1 X
    if [ "$X" == xx ]
    then
      echo "Running automated build."
      HANDOFF=/mnt/init
    fi
  fi
  exec /sbin/oneit -c /dev/"$CONSOLE" "$HANDOFF"

# If we're not PID 1, it's probably a chroot.
else
  [ ! -z "$(grep "default for QEMU" /etc/resolv.conf)" ] &&
    echo "nameserver 8.8.8.8" > /etc/resolv.conf

  # If we have no RTC, try using ntp to set the clock
  [ "$(date +%s)" -lt 10000000 ] && ntpd -nq -p north-america.pool.ntp.org

  # Switch to a shell with command history.

  echo Type exit when done.
  /bin/ash
  cd /
  umount ./dev
  umount ./sys
  umount ./proc
  sync
fi
