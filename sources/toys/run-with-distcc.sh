#!/bin/bash

# Wrapper script that sets up distcc on the host and tells the native build
# where to find it, then hands off to run-with-home.sh

if [ ! -f "$1"/distcc/gcc ]
then
  echo "Usage: $0 cross-compiler-path" >&2
  exit 1
fi

# Run the distcc daemon on the host system with $PATH restricted to the
# cross compiler's symlinks.

DCC="$(which distccd)"
if [ -z "$DCC" ]
then
  echo 'No distccd in $PATH'
  exit 1
fi

PATH="$(readlink -f "$1/distcc")" "$DCC" --listen 127.0.0.1 --log-stderr \
  --log-level error --daemon -a 127.0.0.1 2>distccd.log # --no-detach

# Prepare some environment variables for run-qemu.sh

export DISTCC_PATH_PREFIX=/tools/distcc:
CPUS=$[$(echo /sys/devices/system/cpu/cpu[0-9]* | wc -w)+1]
export KERNEL_EXTRA="DISTCC_HOSTS=10.0.2.2 CPUS=$CPUS $KERNEL_EXTRA"

# Hand off to run-with-home.sh in the directory this script's running from.

"$(readlink -f "$(which $0)" | sed -e 's@\(.*/\).*@\1@')"run-with-home.sh

# Cleanup afterwards: Kill child processes we started (I.E. distccd).

kill `jobs -p`
