#!/bin/sh

./download.sh &&
./host-tools.sh $1 &&
./cross-compiler.sh $1 &&
./mini-native.sh $1
