#!/bin/bash

# Iterate through every target architecture, running rest of command line
# on each $TARGET.

# If $FORK is set, run them in parallel with filtered output.

. sources/utility_functions.sh || exit 1

[ -z "${ARCHES}" ] &&
  ARCHES="$(ls sources/targets)"

for TARGET in $ARCHES
do
  [ ! -f "sources/targets/$TARGET" ] && continue
  announce "$TARGET running"
  maybe_fork "$* 2>&1 | maybe_quiet"
done

wait
