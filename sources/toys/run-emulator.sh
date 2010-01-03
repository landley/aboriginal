#!/bin/bash

# The following environment variables affect the behavior of this script:

# HDB - Image file to use for -hdb on /home (none if blank)
# HDBMEGS - Number of megabytes to create
# HDC - Image file to use for -hdc on /mnt (none of blank)
# QEMU_MEMORY - number of megabytes of memory for qemu (defaults to 128)

# Also, to use the distcc accelerator you need to have distccd and $ARCH-cc
# in the $PATH.

[ ! -z "$QEMU_MEMORY" ] && QEMU_EXTRA="-m $QEMU_MEMORY $QEMU_EXTRA"

# Should we set up an ext3 image as a second virtual hard drive for /home?

if [ ! -z "$HDB" ]
then
  if [ ! -e "$HDB" ]
  then

    # If we don't already have an hdb image, should we set up a sparse file and
    # format it ext3?

    if [ ! -z "$HDBMEGS" ]
    then
      # Some distros don't put /sbin:/usr/sbin in the $PATH for non-root users.
      [ -z "$(which  mke2fs)" ] && export PATH=/sbin:/usr/bin:$PATH

      dd if=/dev/zero of="$HDB" bs=1024 seek=$[$HDBMEGS*1024-1] count=1 &&
      mke2fs -b 1024 -F "$HDB" -i 4096 &&
      tune2fs -j -c 0 -i 0 "$HDB"

      [ $? -ne 0 ] && exit 1
    fi
  fi
  WITH_HDB="-hdb $HDB"
fi

[ ! -z "$HDC" ] && [ -e "$HDC" ] && WITH_HDC="-hdc $HDC"

# Start of distcc setup

unique_port()
{
  # Try to find a unique port number for each running instance of the program.

  # To reduce the chance of the port already being in use by another program,
  # we use a range either before or after that used by normal programs, but
  # beyond that allocated to most persistent demons.  There's a small chance
  # even these ports are already in use, but this at least prevents
  # simultaneous run-emulator instances for different targets from
  # trivially interfering with each other.

  START=8192
  RANGE=$[$(awk '{print $1}' /proc/sys/net/ipv4/ip_local_port_range)-$START]
  if [ $RANGE -lt 1 ]
  then
    START=$[$(awk '{print $2}' /proc/sys/net/ipv4/ip_local_port_range)]
    RANGE=$[65535-$START]
  fi
  echo $[($$%$RANGE)+$START]
}

# The ARCH gets substituted in here by system-image.sh

ARCH=

# If the cross compiler isn't in the $PATH, look for it in the current
# directory and the user's home directory.

DISTCC_PATH="$(which $ARCH-cc 2>/dev/null | sed 's@\(.*\)/.*@\1@')"

if [ -z "$DISTCC_PATH" ]
then
  for i in {"$(pwd)","$HOME"/}{,simple-}cross-compiler-"$ARCH"/bin
  do
    [ -f "$i/$ARCH-cc" ] && DISTCC_PATH="$i"
    break
  done
fi

if [ -z "$(which distccd)" ]
then
  echo 'No distccd in $PATH, acceleration disabled.'
elif [ -z "$DISTCC_PATH" ]
then
  echo "No $ARCH-cc in "'$PATH'", acceleration disabled."
else

  # Populate a directory full of symlinks to the cross compiler using the
  # unprefixed names distccd will try to use.

  mkdir -p "distcc_links" &&
  for i in $(cd "$DISTCC_PATH"; ls $ARCH-* | sed "s/^$ARCH-//" )
  do
    ln -sf "$DISTCC_PATH/$ARCH-$i" "distcc_links/$i"
  done
  if [ -e "$DISTCC_PATH/$ARCH-rawgcc" ]
  then
    for i in cc gcc g++ c++
    do
      ln -sf "$DISTCC_PATH/$ARCH-rawgcc" distcc_links/$i
    done
  fi

  # Run the distcc daemon on the host system with $PATH restricted to the
  # cross compiler binaries.

  # Note that we tell it --no-detach and background it ourselves so jobs -p can
  # find it later to kill it after the emulator exits.

  PORT=$(unique_port)
  CPUS=$[$(echo /sys/devices/system/cpu/cpu[0-9]* | wc -w)*2]
  PATH="$(pwd)/distcc_links" "$(which distccd)" --no-detach --daemon \
    --listen 127.0.0.1 -a 127.0.0.1 -p $PORT --jobs $CPUS \
    --log-stderr --verbose 2>distccd.log &

  # Clean up afterwards: Kill child processes we started (I.E. distccd).
  trap "kill $(jobs -p)" EXIT

  # When background processes die, they should do so silently.
  disown $(jobs -p)

  # Let the QEMU launch know we're using distcc.

  DISTCC_PATH_PREFIX=/usr/distcc:
  KERNEL_EXTRA="DISTCC_HOSTS=10.0.2.2:$PORT/$CPUS CPUS=$CPUS $KERNEL_EXTRA"
fi

# Kill our child processes on exit.

trap "pkill -P$$" EXIT

# The actual emulator invocation command gets appended here by system-image.sh

