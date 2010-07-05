#!/bin/bash

# Iterate through every target architecture, running rest of command line
# on each $TARGET.

# If $FORK is set, run them in parallel with filtered output.

. sources/functions.sh || exit 1

[ -z "${ARCHES}" ] &&
  ARCHES="$(cd sources/targets/; ls | grep -v '^hw-')"

for TARGET in $ARCHES
do
  maybe_fork "$* | maybe_quiet"
done

wait
