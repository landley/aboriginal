make_hdb()
{
  # Some distros don't put /sbin:/usr/sbin in the $PATH for non-root users.
  if [ -z "$(which  mke2fs)" ] || [ -z "$(which tune2fs)" ]
  then
    export PATH=/sbin:/usr/sbin:$PATH
  fi

  truncate -s ${HDBMEGS}m "$HDB" &&
  mke2fs -q -b 1024 -F "$HDB" -i 4096 &&
  tune2fs -j -c 0 -i 0 "$HDB"

  [ $? -ne 0 ] && exit 1
}
