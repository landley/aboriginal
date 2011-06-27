#!/usr/bin/python

# Filter out baseconfig entries from output of miniconfig.sh

import os,sys

if len(sys.argv) != 3:
  sys.stderr.write("usage: filter.py baseconfig mini.config\n")
  sys.exit(1)

baseconfig=file(sys.argv[1]).readlines()
miniconfig=file(sys.argv[2]).readlines()

for i in baseconfig:
  if i in miniconfig:
    miniconfig.remove(i)

print "".join(miniconfig),
