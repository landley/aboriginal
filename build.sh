#!/bin/sh

./download.sh &&
./cross-compiler.sh $1 &&
./mini-native.sh $1
