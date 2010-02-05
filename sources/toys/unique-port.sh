#!/bin/bash

unique_port()
{
  # Try to find a unique port number for each running instance of the program.

  # To reduce the chance of the port already being in use by another program,
  # we use a range either before or after that used by normal programs, but
  # beyond that allocated to most persistent demons.  There's a small chance
  # even these ports are already in use, but this at least prevents
  # simultaneous run-emulator instances for different targets from
  # trivially interfering with each other.

  START=8192
  RANGE=$[$(awk '{print $1}' /proc/sys/net/ipv4/ip_local_port_range)-$START]
  if [ $RANGE -lt 1 ]
  then
    START=$[$(awk '{print $2}' /proc/sys/net/ipv4/ip_local_port_range)]
    RANGE=$[65535-$START]
  fi
  echo $[($$%$RANGE)+$START]
}
