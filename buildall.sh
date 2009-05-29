#!/bin/bash

# Build every target architecture, creating out-$ARCH.txt log files.
# If $FORK is set, build them in parallel.

. sources/functions.sh || exit 1

rm -rf build

[ -z "${ARCHES}" ] &&
  ARCHES="$(cd sources/targets/; ls | grep -v '^hw-')"
[ -z "$ALLARCHES" ] &&
  ALLARCHES="${ARCHES} $(cd sources/targets; ls | grep '^hw-')"

DO_SKIP_STAGE_TARBALLS="$SKIP_STAGE_TARBALLS"
[ ! -z "$CROSS_COMPILERS_EH" ] && DO_SKIP_STAGE_TARBALLS=1

# Run command in the background or foreground, depending on $FORK

doforklog()
{
  [ -z "$LOG" ] && LOG=/dev/null

  if [ ! -z "$FORK" ]
  then
    $* 2>&1 | tee "$LOG" | grep '^===' &
  else
    $* 2>&1 | tee "$LOG"
  fi
}

# Perform initial setup that doesn't parallelize well: Download source,
# build host tools, extract source.

(./download.sh && ./host-tools.sh && ./download.sh --extract || dienow ) 2>&1 |
  tee out-host.txt

# Create README file (requires build/sources to be extracted)

cat packages/MANIFEST sources/toys/README.footer > build/README || exit 1

# Build all the initial cross compilers, possibly in parallel

# These are dynamically linked on the host, --disable-shared, no uClibc++.

for i in ${ARCHES}
do
  LOG=build/cross-dynamic-${i}.txt \
    SKIP_STAGE_TARBALLS="$DO_SKIP_STAGE_TARBALLS" \
    doforklog ./cross-compiler.sh $i
done

wait4background

# Should we do the static compilers via canadian cross?

if [ ! -z "$CROSS_COMPILERS_EH" ]
then

  # Build the static cross compilers, possibly in parallel

  # These are statically linked against uClibc on the host (for portability),
  # built --with-shared, and have uClibc++ installed.

  # To build each of these we need two existing cross compilers: one for
  # the host (to build the executables) and one for the target (to build
  # the libraries).

  for i in ${ARCHES}
  do
    LOG=build/cross-static-${i}.txt SKIP_STAGE_TARBALLS=1 BUILD_STATIC=1 \
      FROM_ARCH="$CROSS_COMPILERS_EH" NATIVE_TOOLCHAIN=only \
      STAGE_NAME=cross-static doforklog ./root-filesystem.sh $i 
  done

  wait4background

  # Replace the dynamic cross compilers with the static ones, and tar 'em up.

  rm -rf build/dynamic &&
  mkdir -p build/dynamic &&
  mv build/cross-compiler-* build/dynamic || exit 1

  for i in ${ARCHES}
  do
    mv build/{root-filesystem-$i,cross-compiler-$i} &&
    doforklog tar cjfC build/cross-compiler-$i.tar.bz2 build cross-compiler-$i
  done

  wait4background

fi

if [ ! -z "$NATIVE_COMPILERS_EH" ]
then

  # Build static native compilers for each target, possibly in parallel

  for i in ${ARCHES}
  do
    LOG=build/native-static-${i}.txt SKIP_STAGE_TARBALLS=1 BUILD_STATIC=1 \
      NATIVE_TOOLCHAIN=only STAGE_NAME=native-static \
      doforklog ./root-filesystem.sh $i
  done

  wait4background

  for i in ${ARCHES}
  do
    mv build/{root-filesystem-$i,natemp-$i} &&
    doforklog tar cjfC build/native-compiler-$i.tar.bz2 build/natemp-"$i" .
  done

  wait4background

  rm -rf build/natemp-* &
fi

# Now that we have our cross compilers, use them to build root filesystems.

for i in ${ARCHES}
do
  [ -f "build/cross-compiler-$i.tar.bz2" ] &&
    LOG=build/root-filesystem-$i.txt doforklog ./root-filesystem.sh $i
done

wait4background

# Package all targets, including hw-targets.

for i in ${ALLARCHES}
do
  LOG=build/system-image-$i.txt doforklog ./system-image.sh $i
done

wait4background 0
