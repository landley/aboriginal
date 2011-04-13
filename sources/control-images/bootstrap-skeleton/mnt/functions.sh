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
