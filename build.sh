#!/bin/bash

./download.sh &&
./host-tools.sh &&
./cross-compiler.sh $1 &&
./mini-native.sh $1
