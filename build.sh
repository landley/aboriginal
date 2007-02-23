#!/bin/bash

# Just for argument checking 

./include.sh $1 || exit 1

# Run the steps in order

./download.sh &&
./host-tools.sh &&
./cross-compiler.sh $1 &&
./mini-native.sh $1 &&
./package-mini-native.sh $1
