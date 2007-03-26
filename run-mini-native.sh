#!/bin/sh

source include.sh

INIT="$2"
[ -z "$INIT" ] && INIT=/tools/bin/sh
run_emulator build/image-"$1".ext2 build/mini-native-"$1"/zImage-"$1" \
	"rw init=$INIT panic=1 PATH=/tools/bin"
