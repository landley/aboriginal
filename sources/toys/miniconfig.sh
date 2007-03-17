#!/bin/sh

# miniconfig.sh copyright 2005 by Rob Landley <rob@landley.net>
# Licensed under the GNU General Public License version 2.

# Run this in the linux kernel build directory with a starting file, and
# it creates a file called mini.config with all the redundant lines of that
# .config removed.  The starting file must match what the kernel outputs.
# If it doesn't, then run "make oldconfig" on it to get one that does.

if [ $# -ne 1 ] || [ ! -f "$1" ]
then
  echo "Usage: miniconfig.sh configfile" 
  exit 1
fi

if [ "$1" == ".config" ]
then
  echo "It overwrites .config, rename it and try again."
  exit 1
fi

make allnoconfig KCONFIG_ALLCONFIG="$1" > /dev/null
if [ "$(diff .config "$1" | wc -l)" -ne 4 ]
then
  echo Sanity test failed, run make oldconfig on this file:
  diff -u .config "$1"
  exit 1
fi

cp $1 mini.config
echo "Calculating mini.config..."

LENGTH=`cat $1 | wc -l`

# Loop through all lines in the file 
I=1
while true
do
  if [ $I -gt $LENGTH ]
  then
    exit
  fi
  sed -n "${I}!p" mini.config > .config.test
  # Do a config with this file
  make allnoconfig KCONFIG_ALLCONFIG=.config.test > /dev/null

  # Compare.  The date changes so expect a small difference each time.
  D=`diff .config $1 | wc -l`
  if [ $D -eq 4 ]
  then
    mv .config.test mini.config
    LENGTH=$[$LENGTH-1]
  else
    I=$[$I + 1]
  fi
  echo -n -e $I/$LENGTH lines `cat mini.config | wc -c` bytes "\r"
done
echo
