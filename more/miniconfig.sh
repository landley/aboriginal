#!/bin/bash

# miniconfig.sh copyright 2005 by Rob Landley <rob@landley.net>
# Licensed under the GNU General Public License version 2.

# Run this in the linux kernel build directory with a starting file, and
# it creates a file called mini.config with all the redundant lines of that
# .config removed.  The starting file must match what the kernel outputs.
# If it doesn't, then run "make oldconfig" on it to get one that does.

# A miniconfig file is essentially the list of symbols you'd have to switch
# on if you started from "allnoconfig" and then went through menuconfig
# selecting what you wanted.  It's just the list of symbols you're interested
# in, without including the ones set automatically by dependency checking.

# To use a miniconfig: make allnoconfig KCONFIG_ALLCONFIG=/path/to/mini.conf

# Miniconfig is more easily human-readable than a full .config file, and in
# some ways more version-independent than full .config files.  On the other
# hand, when you update to a new kernel it won't get default values for newly
# created symbols (they'll be off if they didn't exist before and thus weren't
# in your "I need this and this and this" checklist), which can cause problems.

# See sources/more/migrate_kernel.sh for a script that expands a miniconfig
# to a .config under an old kernel version, copies it to a new version,
# runs "make oldconfig" to update it, creates a new mini.config from the
# result, and then shows a diff so you can see whether you want the new symbols.

export KCONFIG_NOTIMESTAMP=1

if [ $# -ne 1 ]
then
  echo "Usage: miniconfig.sh configfile" 
  exit 1
fi

if [ ! -f "$1" ]
then
  echo "Couldn't find "'"'"$1"'"'
  exit 1
fi

if [ "$1" == ".config" ]
then
  echo "It overwrites .config, rename it and try again."
  exit 1
fi

make allnoconfig KCONFIG_ALLCONFIG="$1" > /dev/null
# Shouldn't need this, but kconfig goes "boing" at times...
yes "" | make oldconfig > /dev/null 
if ! cmp .config "$1"
then
  echo Sanity test failed, normalizing starting configuration...
  diff -u "$1" .config
fi
cp .config .big.config

# Speed heuristic: remove all blank/comment lines
grep -v '^[#$]' .config | grep -v '^$' > mini.config
# This should never fail, but kconfig is so broken it does sometimes.
make allnoconfig KCONFIG_ALLCONFIG=mini.config > /dev/null
if ! cmp .config "$1"
then
  echo Insanity test failed: reversing blank line removal heuristic.
  cp .big.config mini.config
fi
#cp .config mini.config

echo "Calculating mini.config..."

LENGTH=`cat mini.config | wc -l`
OLDLENGTH=$LENGTH

# Loop through all lines in the file 
I=1
while true
do
  [ $I -gt $LENGTH ] && break
  sed -n "$I,$(($I+${STRIDE:-1}-1))!p" mini.config > .config.test
  # Do a config with this file
  rm .config
  make allnoconfig KCONFIG_ALLCONFIG=.config.test 2>/dev/null | head -n 1000000 > /dev/null
  # Compare.  Because we normalized at the start, the files should be identical.
  if cmp -s .config .big.config
  then
    # Found unneeded line(s)
    mv .config.test mini.config
    LENGTH=$(($LENGTH-${STRIDE:-1}))
    # Cosmetic: if stride tests off the end don't show total length less
    # than number of entries found.
    [ $I -gt $LENGTH ] && LENGTH=$(($I-1))
    # Special case where we know the next line _is_ needed: stride 2 failed
    # but we discarded the first line
    [ -z "$STRIDE" ] && [ ${OLDSTRIDE:-1} -eq 2 ] && I=$(($I+1))
    STRIDE=$(($STRIDE+1))
    OLDSTRIDE=$STRIDE
  else
    # That hunk was needed
    if [ ${STRIDE:-1} -le 1 ]
    then
      I=$(($I+1))
      OLDSTRIDE=
    fi
    STRIDE=
  fi
  echo -n -e "\r[${STRIDE:-1}] $[$I-1]/$LENGTH lines $(cat mini.config | wc -c) bytes $[100-((($LENGTH-$I)*100)/$OLDLENGTH)]%    "
done
rm .big.config
echo
