#!/bin/bash

# Build every target architecture, creating out-$ARCH.txt log files.
# If $FORK is set, build them in parallel.

. sources/functions.sh || exit 1

rm -rf build

BASEARCHES="$(cd sources/targets/; ls | grep -v '^hw-')"

# Run command in the background or foreground, depending on $FORK

doforklog()
{
  [ -z "$LOG" ] && LOG=/dev/null

  [ ! -z "$FORK" ] &&
    ( ($*) 2>&1 | tee "$LOG" | grep '^===' &) ||
      ($*) 2>&1 | tee "$LOG"
}

# Perform initial setup that doesn't parallelize well: Download source,
# build host tools, extract source.

(./download.sh && ./host-tools.sh && ./download.sh --extract ) 2>&1 |
  tee out-host.txt

# Create README file (requires build/sources to be extracted)

(do_readme && cat sources/toys/README.footer) | tee build/README

# Build all the initial cross compilers

# These are dynamically linked on the host, --disable-shared, no uClibc++.

for i in $BASEARCHES
do
  LOG=build/cross-dynamic-${i}.txt \
  SKIP_STAGE_TARBALLS=1 doforklog ./cross-compiler.sh $i
done

wait4background 0

# Should we do the static compilers via canadian cross?

if [ ! -z "$CROSS_COMPILERS_EH" ]
then

# Build the static cross compilers
# These are statically linked against uClibc on the host (for portability),
# built --with-shared, and have uClibc++ installed.

for i in $BASEARCHES
do
  LOG=build/cross-static-${i}.txt SKIP_STAGE_TARBALLS=1 \
    BUILD_STATIC=1 FROM_ARCH=i686 NATIVE_TOOLCHAIN=only \
    doforklog ./root-filesystem.sh $i 
done

wait4background 0


# Replace the dynamic cross compilers with the static ones, and tar 'em up.

rm -rf build/dynamic &&
mkdir -p build/dynamic &&
mv build/cross-compiler-* build/dynamic || exit 1

for i in $BASEARCHES
do
  mv build/{root-filesystem-$i,cross-compiler-$i} &&
  mv root-filesystem-$i cross-$i &&
  doforklog tar czf cross-compiler-$i.tar.bz2 cross-compiler-$i
done

wait4background 0

fi

# Now build hardware targets using the static cross compilers above.
# (Smoke test, really.)

for i in $(cd sources/targets; ls)
do
  doforklog ./build.sh 2>&1 | tee out-$i.txt
done

# Wait for hardware targets to complete

wait4background 0
