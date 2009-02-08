#!/bin/bash

# Parse command line arguments

while [ ! -z "$1" ]
do
  if [ "$1" == "--make-hdb" ]
  then
    shift
    HDBMEGS="$1"
  elif [ "$1" == "--with-hdb" ]
  then
    shift
    HDB="$1"
  elif [ "$1" == "--with-distcc" ]
  then
    DCC="$(which distccd)"
    if [ -z "$DCC" ]
    then
      echo 'No distccd in $PATH' >&2
      exit 1
    fi

    shift
    DISTCC_PATH="$1"
  elif [ "$1" == "--memory" ]
  then
    shift
    MEMORY="-m $1"
  else
    (
      echo "unknown argument $1"
      echo 'Usage: run-emulator.sh [OPTIONS]'
      echo '	--make-hdb $MEGS - create a sparse image (if none exists) to mount on /home'
      echo '	--with-hdb $FILE - Use an image file name other than hdb.img'
      echo '	--with-distcc $DISTCC_PATH - set up distcc accelerator.'
      echo '		Argument is path to cross compiler.'
      echo '	--memory $MEGS - Tell emulator to use this many megabytes of memory.'
      echo '		Default is 128 megs for 32 bit targets, 256 megs for 64 bit.'
    ) >&2
    exit 1
  fi

  shift
done

if [ ! -z "$DISTCC_PATH" ]
then

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
  PORT=$[($$%$RANGE)+$START]

  # Run the distcc daemon on the host system with $PATH restricted to the
  # cross compiler binaries.

  # Note that we tell it --no-detach and background it oursleves so jobs -p can
  # find it later to kill it after the emulator exits.

  PATH="$(readlink -f "$DISTCC_PATH"/*-unknown-linux/bin)" "$DCC" --listen 127.0.0.1 \
    --no-detach --log-file distccd.log --log-level warning --daemon \
    -a 127.0.0.1 -p $PORT &
  # Cleanup afterwards: Kill child processes we started (I.E. distccd).
  trap "kill $(jobs -p)" EXIT

  # Prepare some environment variables for run-qemu.sh

  DISTCC_PATH_PREFIX=/tools/distcc:
  CPUS=$[$(echo /sys/devices/system/cpu/cpu[0-9]* | wc -w)*2]
  KERNEL_EXTRA="DISTCC_HOSTS=10.0.2.2:$PORT CPUS=$CPUS $KERNEL_EXTRA"
fi

# Should we set up an ext3 image as a second virtual hard drive for /home?

# Default to image "hdb.img"
[ -z "$HDB" ] && HDB="hdb.img"

if [ ! -e "$HDB" ]
then

  # If we don't already have an hdb image, should we set up a sparse file and
  # format it ext3?

  if [ ! -z "$HDBMEGS" ]
  then
    # Some distros don't put /sbin:/usr/sbin in the $PATH for non-root users.
    [ -z "$(which mke2fs)" ] && export PATH=/sbin:/usr/sbin:$PATH

    dd if=/dev/zero of="$HDB" bs=1024 seek=$[$HDBMEGS*1024-1] count=1 &&
    mke2fs -b 1024 -F "$HDB" -i 4096 &&
    tune2fs -j -c 0 -i 0 "$HDB"

    [ $? -ne 0 ] && exit 1
  fi
fi

[ -e "$HDB" ] && WITH_HDB="-hdb $HDB"

# The actual emulator invocation command gets appended here

