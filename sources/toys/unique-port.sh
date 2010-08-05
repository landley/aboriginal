unique_port()
{
  # Try to find an unused port number for each running instance of the program.

  START=8192
  RANGE=$[$(awk '{print $1}' /proc/sys/net/ipv4/ip_local_port_range)-$START]
  if [ $RANGE -lt 8 ]
  then
    START=$[$(awk '{print $2}' /proc/sys/net/ipv4/ip_local_port_range)]
    RANGE=$[65535-$START]
    if [ $RANGE -lt 8 ]
    then
      START=16384
      RANGE=32768
    fi
  fi
  echo $[($$%$RANGE)+$START]
}
