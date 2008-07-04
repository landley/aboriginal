#!/bin/bash

# Quick script to mine the output of "RECORD_COMMANDS=1 ./forkbomb.sh --nofork"
# for lists of commands used in each stage.

# Output the list of commands used in a command log.

function mine_commands()
{
  awk '{print $1}' $1 | sort -u
}

# Sort the log files into groups, then iterate through the result

for i in `(for i in build/cmdlines-*/*; do echo $i; done) | sed 's@.*/cmdlines\.@@' | sort -u`
do
  # Start of new group, announce build stage we're looking at.
  FIRST=""
  echo
  echo Checking $i

  # Loop through this build stage in each architecture.
  for j in build/cmdlines-*/cmdlines.$i
  do
    NAME="$(echo $j | sed 's@build/cmdlines-\([^/]*\)/.*@\1@')"

    if [ -z "$FIRST" ]
    then
      # Show all commands in first architecture.
      echo $NAME: $(mine_commands $j)
      FIRST=$j
    else
      # Show commands that differ from first architecture (if any).
      X=$(sort <(mine_commands $FIRST) <(mine_commands $j) | uniq -u)
      [ ! -z "$X" ] && echo $NAME: $X
    fi
  done
done
