#!/bin/bash

source sources/include.sh && read_arch_dir "$1" || exit 1

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
else
  echo "Can't run hello world" >&2
  dienow
fi
