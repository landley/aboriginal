#!/bin/bash

# List the commands used to build each architecture.

# If given an argument it's the architecture to compare others against,
# which shows just the extra commands used by those other architectures.

# Mines the output created by build.sh after record-commands.sh.

COMPARE="$1"

# Output the list of commands used in a command log.

function mine_commands()
{
  awk '{print $1}' build/logs/cmdlines.$1.* | sort -u
}

# Iterate through architectures

for i in `ls -1 build/logs/cmdlines.* | sed 's@.*/cmdlines\.\([^.]*\).*@\1@' | sort -u`
do
  [ "$COMPARE" == "$i" ] && continue

  # Start of new group, announce build stage we're looking at.
  echo
  echo -n Checking $i:

  if [ -z "$COMPARE" ]
  then
    # Show all commands in first architecture.
    echo $(mine_commands $i)
  else
    # Show commands that differ from first architecture (if any).
    echo $(sort <(mine_commands $COMPARE) <(mine_commands $i) | uniq -u)
  fi
done
