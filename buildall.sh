#!/bin/bash

# Build every target architecture, creating out-$ARCH.txt log files.
# If $FORK is set, build them in parallel.

. sources/functions.sh || exit 1

# Build one architecture, capturing log output.

buildit()
{
  (time ./build.sh $1) 2>&1 | tee out-$1.txt
}

# Build in the background or foreground depending on $FORK

buildlog()
{
  [ ! -z "$FORK" ] && (buildit $i | grep '^===' &) || buildit $i
}

# Perform initial setup that doesn't parallelize well.  Download source,
# build host tools, extract source.

(./download.sh && ./host-tools.sh && ./download.sh --extract ) 2>&1 | tee out-host.txt

# Create README file (requires build/sources to be extracted)

(do_readme && cat sources/toys/README.footer) | tee build/README

# Build architectures

for i in $(cd sources/targets/; ls | grep -v '^hw-')
do
  buildlog $i
done

# Wait for architectures to complete

wait4background 0

# Now build hardware targets

for i in $(cd sources/targets; ls | grep '^hw-')
do
  buildlog $i
done

# Wait for hardware targets to complete

wait4background 0
