# splice hda into /
cp -rFs /usr/overlay/. /

# cleanup copy of _this_ script, and plug gcc so search stops

if [ -z "$DISTCC_HOSTS" ]
then
  echo "Not using distcc."
else
  echo "Distcc acceleration enabled."
  PATH="/usr/distcc:$PATH"

  # distcc does realpath() which is a problem because ccwrap won't use
  # things added to the relocated include directory if you call the one
  # at the original location.
  rm /usr/bin/cc &&
  echo -e "#!/bin/ash\nexec /usr/overlay/usr/bin/cc" > /usr/bin/cc &&
  chmod +x /usr/bin/cc || exit 1
fi

if [ -e /mnt/init ]
then
  X=xx
  echo "Press any key for command line..."
  read -t 3 -n 1 X
  if [ "$X" == xx ]
  then
    echo "Running automated build."
    HANDOFF=/mnt/init
  fi
fi
