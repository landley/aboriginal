#!/bin/sh

source include.sh

run_emulator build/image-"$1".ext2 build/mini-native-"$1"/zImage-"$1" \
	"-nographic rw init=/tools/bin/sh panic=1 PATH=/tools/bin"
