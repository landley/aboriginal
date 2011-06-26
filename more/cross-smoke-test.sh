#!/bin/bash

# Perform a smoke test on a target's cross compiler by building "hello world"
# and attempting to run it under QEMU application emulation.

source sources/include.sh && load_target "$1" || exit 1

# Build statically linked hello world, if necessary

if [ ! -e "$WORK/hello" ]
then
  "${ARCH}-gcc" -Os -static "${SOURCES}/toys/hello.c" -o "$WORK"/hello

  if [ $? -ne 0 ]
  then
    echo "Compiler doesn't seem to work" >&2
    dienow
  fi
fi

# Attempt to run statically linked hello world

RESULT="$(PATH="$OLDPATH" qemu-"$QEMU_TEST" "$WORK/hello")"
if [ "$RESULT" == "Hello world!" ]
then
  echo "Cross toolchain seems to work."
  exit 0
else
  echo "Can't run hello world" >&2
  exit 1
fi
