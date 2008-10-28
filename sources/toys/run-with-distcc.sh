#!/bin/bash

# Wrapper script that sets up distcc on the host and tells the native build
# where to find it, then hands off to run-with-home.sh

if [ ! -f "$1"/*-unknown-linux/bin/gcc ]
then
  echo "Usage: $0 cross-compiler-path" >&2
  exit 1
fi

# Run the distcc daemon on the host system with $PATH restricted to the
# cross compiler's symlinks.

# Note that we tell it --no-detach and background it oursleves so jobs -p can
# find it later to kill it after the emulator exits.

DCC="$(which distccd)"
if [ -z "$DCC" ]
then
  echo 'No distccd in $PATH'
  exit 1
fi

function portno()
{
  START=8192
  RANGE=$[$(awk '{print $1}' /proc/sys/net/ipv4/ip_local_port_range)-$START]
  if [ $RANGE -lt 1 ]
  then
    START=$[$(awk '{print $2}' /proc/sys/net/ipv4/ip_local_port_range)]
    RANGE=$[65535-$PORT]
  fi
  echo $[($$%$RANGE)+$START]
}

PORT=$(portno)
PATH="$(readlink -f "$1"/*-unknown-linux/bin)" "$DCC" --listen 127.0.0.1 \
  --no-detach --log-file distccd.log --log-level warning --daemon \
  -a 127.0.0.1 -p $PORT &
# Cleanup afterwards: Kill child processes we started (I.E. distccd).
trap "kill $(jobs -p)" EXIT

# Prepare some environment variables for run-qemu.sh

export DISTCC_PATH_PREFIX=/tools/distcc:
CPUS=$[$(echo /sys/devices/system/cpu/cpu[0-9]* | wc -w)+1]
export KERNEL_EXTRA="DISTCC_HOSTS=10.0.2.2:$PORT CPUS=$CPUS $KERNEL_EXTRA"

# Hand off to run-with-home.sh in the directory this script's running from.

"$(readlink -f "$(which $0)" | sed -e 's@\(.*/\).*@\1@')"run-with-home.sh

echo
