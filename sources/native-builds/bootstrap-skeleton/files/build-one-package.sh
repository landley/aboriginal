#!/bin/sh

source /mnt/functions.sh || exit 1

# build $1 using manifest file $2

# Is it already installed?

if [ ! -z "$2" ] && [ -z "$FORCE" ] && grep -q "$1" "$2"
then
  echo "$1 already installed"
  exit 0
fi

set_titlebar "$1"

if [ -d "/mnt/packages/$1" ]
then

  # Snapshot source

  cd /home &&
  rm -rf "/home/$1" &&
  cp -sfR "/mnt/packages/$1" "$1" &&
  cd "$1" || exit 1

  # Lobotomize config.guess so it won't complain about unknown target types.

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

if ! time "/mnt/build/${1}.$EXT"
then
  echo "$1" died >&2
  exit 1
fi

# Add file to manifest, removing previous version (if any).

if [ ! -z "$2" ]
then
  sed -i -e "/$1/d" "$2" &&
  echo "$1" >> "$2" || exit 1
fi

if [ -d "/mnt/packages/$1" ]
then

  # Delete copy of source if build succeeded

  cd /home &&
  rm -rf "$1" &&
  sync || exit 1
fi
