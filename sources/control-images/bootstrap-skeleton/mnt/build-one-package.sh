#!/bin/ash

# Yes, ash.  Because neither bash 2 nor hush support -o pipefail

set -o pipefail

source /mnt/functions.sh || exit 1

# build $1

set_titlebar "$1"

# Three types of /mnt/build scripts:
#
# $1.nosrc - no source code in /mnt/build, perform no setup/cleanup.
# $1.sh - source is symlink tree to "/mnt/build/$1".  This is faster and uses
#         less disk space but confuses some packages.
# $1.nolink - source is conventional copy of /mnt/build/$1

if [ ! -e "/mnt/build/$1.nosrc" ]
then
  [ -e "/mnt/build/$1.nolink" ] && LINKTYPE=dp || LINKTYPE=s

  # Snapshot source from /mnt/build/$1 to /home/$1

  cd /home &&
  rm -rf "/home/$1" &&
  cp -${LINKTYPE}fR "/mnt/packages/$1" "$1" &&
  cd "$1" || exit 1

  # Lobotomize config.guess so it won't complain about unknown target types.
  # 99% of packages do not care, but autoconf throws a temper tantrum if
  # the version of autoconf that created this back when the package shipped
  # didn't know what a microblaze or hexagon was.  Repeat after me:
  #   "Autoconf is useless"

  for guess in $(find . -name config.guess)
  do
    rm "$guess" &&
    echo -e "#!/bin/sh\ngcc -dumpmachine" > "$guess" || exit 1
  done
  EXT=sh
else
  EXT=nosrc
fi

# Call package build script

mkdir -p /home/log
time "/mnt/build/$1".* 2>&1 | tee "/home/log/$1.log"
if [ $? -ne 0 ]
then
  echo "$1" died >&2
  exit 1
fi

# Delete copy of source if build succeeded

if [ ! -z "$LINKTYPE" ]
then
  cd /home &&
  rm -rf "$1" &&
  sync || exit 1
fi
