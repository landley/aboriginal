#!/bin/echo This file is sourced not run

upload_result()
{
  ftpput $FTP_SERVER -P $FTP_PORT "$1-$HOST" "$1"
}

set_titlebar()
{
  echo -en "\033]2;($HOST) $1\007"
  echo === "$1"
}

dotprogress()
{
  while read i; do echo -n .; done; echo
}

do_in_chroot()
{
  # Copy root filesystem into a new chroot directory and restart in there.

  CHROOT="$1"
  shift

  set_titlebar "Setup chroot"
  mkdir "$CHROOT"
  cp -a /mnt/files/. "$CHROOT"
  find / -xdev | cpio -m -v -p "$CHROOT" | dotprogress
  for i in mnt proc sys dev; do mount --bind /$i "$CHROOT"/$i; done

  echo Chroot
  chroot "$CHROOT" "$@"
  RC=$?

  echo Chroot cleanup
  for i in mnt proc sys dev; do umount "$CHROOT"/$i; done

  return $RC
}
