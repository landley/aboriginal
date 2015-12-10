#!/bin/hush

# Announce version
sed -n 's/PRETTY_NAME="\([^"]*\)"/\1/p' /etc/os-release

export HOME=/home
export PATH=/bin:/sbin

# Mount filesystems
mountpoint -q proc || mount -t proc proc proc
mountpoint -q sys || mount -t sysfs sys sys
mountpoint -q dev || mount -t devtmpfs dev dev || mdev -s
mkdir -p dev/pts
mountpoint -q dev/pts || mount -t devpts dev/pts dev/pts
# /tmp inherited from initmpfs

# If nobody said how many CPUS to use in builds, try to figure it out.
if [ -z "$CPUS" ]
then
  export CPUS=$(echo /sys/devices/system/cpu/cpu[0-9]* | wc -w)
  [ "$CPUS" -lt 1 ] && CPUS=1
fi
export PS1="($HOST:$CPUS) \w \$ "

# When running under qemu, do some more setup
if [ $$ -eq 1 ]
then

  # Note that 10.0.2.2 forwards to 127.0.0.1 on the host.

  # Setup networking for QEMU (needs /proc)
  ifconfig eth0 10.0.2.15
  route add default gw 10.0.2.2

  # If we have no RTC, try rdate instead:
  [ "$(date +%s)" -lt 1000 ] && rdate 10.0.2.2 # or time-b.nist.gov

  # mount hda on /usr/overlay, hdb on /home, and hdc on /mnt, if available

  [ -b /dev/[hsv]da ] &&
    mkdir -p /usr/overlay && mount /dev/[hsv]da /usr/overlay
  [ -b /dev/[hsv]db ] && mount -o noatime /dev/[hsv]db /home && cd /home
  [ -b /dev/[hsv]dc ] && mount -o ro /dev/[hsv]dc /mnt

  [ -z "$CONSOLE" ] &&
    CONSOLE="$(sed -n 's@.* console=\(/dev/\)*\([^ ]*\).*@\2@p' /proc/cmdline)"

  # Call overlay/init if available
  [ -e /usr/overlay/init ] && . /usr/overlay/init

  [ -z "$HANDOFF" ] && echo Type exit when done. && HANDOFF=/bin/hush
  [ -z "$CONSOLE" ] && CONSOLE=console
  exec /sbin/oneit -c /dev/"$CONSOLE" "$HANDOFF"

# If we're not PID 1, it's probably a chroot.
else
  [ ! -z "$(grep "default for QEMU" /etc/resolv.conf)" ] &&
    echo "nameserver 8.8.8.8" > /etc/resolv.conf

  # If we have no RTC, try using ntp to set the clock
  [ "$(date +%s)" -lt 10000000 ] && ntpd -nq -p north-america.pool.ntp.org

  # Switch to a shell with command history.

  echo Type exit when done.
  /bin/hush
  cd /
  umount ./dev/pts
  umount ./dev
  umount ./sys
  umount ./proc
  sync
fi
