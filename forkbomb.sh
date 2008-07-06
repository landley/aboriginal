#!/bin/bash

# Test script to build every target architecture, logging output.
#  With --fork, it builds them in parallel
#  With --nofork, it build them sequentially
#  With --watch, it displays output from an existing parallel build

# Build and package one architecture.

function buildarch()
{
  nice -n 20 ./cross-compiler.sh $1 &&
  nice -n 20 ./mini-native.sh $1 &&
  nice -n 20 ./package-mini-native.sh $1
}

if [ "$1" != "--watch" ] && [ "$1" != "--stat" ]
then
  if [ $# -ne 0 ]
  then

     if [ ! -z "$RECORD_COMMANDS" ]
     then
       mkdir -p build/cmdlines-host &&
       export WRAPPY_LOGDIR=`pwd`/build/cmdlines-host
     fi

    # The first thing we need to do is download the source, build the host
    # tools, and extract the source packages.  This is only done once (not
    # repeated for each architecure), so we do it up front here.  Doing this
    # multiple times in parallel would collide, which is the main reason
    # you can't just run build.sh several times in parallel.

    (touch .kthxbye &&
     nice -n 20 ./download.sh &&
     # host-tools populates one directory with every command the build needs,
     # so we can ditch the old $PATH afterwards.
     nice -n 20 ./host-tools.sh || exit 1

     # Ordinarily the build extracts packages the first time it needs them,
     # but letting multiple builds do that in parallel can collide, so
     # extract them all now up front.  (Adjust the path manually here so we're
     # using the busybox tools rather than the host distro's to do the
     # extract, just to be consistent.)
     if [ -f `pwd`/build/host/busybox ]
     then
       PATH=`pwd`/build/host
     fi
     nice -n 20 ./download.sh --extract &&
     rm .kthxbye) 2>&1 | tee out.txt

     # Exiting from a sub-shell doesn't exit the parent shell, and because
     # we piped the output of the subshell to tee, we can't get the exit code
     # of the subshell.  So we use a sentinel file: if it wasn't deleted, the
     # build went "boing" and should stop now.

     rm .kthxbye 2>/dev/null && exit 1
  fi

  # Loop through each architecture and call "buildarch" as appropriate.

  for i in `cd sources/configs; ls`
  do

    if [ ! -z "$RECORD_COMMANDS" ]
    then
      mkdir -p build/cmdlines-$i || exit 1
      export WRAPPY_LOGDIR=`pwd`/build/cmdlines-host
    fi


    # Build sequentially.

    if [ "$1" == "--nofork" ]
    then
      buildarch $i 2>&1 | tee out-$i.txt || exit 1

    # Build in parallel

    elif [ "$1" == "--fork" ]
    then
      (buildarch $i > out-$i.txt 2>&1 &)&

    # Didn't understand command line arguments, dump help.

    else
      echo "Usage: forkbomb.sh [--fork] [--nofork] [--watch] [--stat]"
      echo -e "\t--nofork  Build all targets one after another."
      echo -e "\t--fork    Build all targets in parallel (needs lots of RAM)."
      echo -e "\t--watch   Restart monitor for --nofork."
      echo -e "\t--stat    Grep logfiles for success/failure after build."
      exit 1
    fi
  done
fi

# Show which builds did or didn't work.

if [ "$1" == "--stat" ]
then
  echo "Success:"
  grep -l system-image- out-*.txt

  echo "Failed:"
  (ls -1 out-*.txt; grep -l system-image- out-*.txt) | sort | uniq -u

  exit 0
fi

# Show progress indicators for parallel build.

if [ "$1" != "--nofork" ]
then
  watch -n 3 'X=; for i in out-*.txt; do /bin/echo -e "$X$i"; X="\n"; tail -n 1 $i; done'
fi
