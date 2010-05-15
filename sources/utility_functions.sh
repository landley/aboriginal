#!/bin/echo "This file is sourced, not run"

# This file contains generic functions, presumably reusable in other contexts.

# Assign (export) a variable only if current value is blank

export_if_blank()
{
  [ -z "$(eval "echo \"\${${1/=*/}}\"")" ] && export "$1"
}

# Create a blank directory at first argument, deleting existing contents if any

blank_tempdir()
{
  # sanity test: never rm -rf something we don't own.
  [ -z "$1" ] && dienow
  touch -c "$1" || dienow

  # Delete old directory, create new one.
  [ -z "$NO_CLEANUP" ] && rm -rf "$1"
  mkdir -p "$1" || dienow
}

# output the sha1sum of a file

sha1file()
{
  sha1sum "$@" | awk '{print $1}'
}

# dienow() is an exit function that works properly even from a subshell.
# (actually_dienow is run in the parent shell via signal handler.)

actually_dienow()
{
  echo -e "\n\e[31mExiting due to errors ($ARCH_NAME $STAGE_NAME $PACKAGE)\e[0m"
  exit 1
}

trap actually_dienow SIGUSR1
TOPSHELL=$$

dienow()
{
  kill -USR1 $TOPSHELL
  exit 1
}

# Turn a bunch of output lines into a much quieter series of periods,
# roughly one per screenfull

dotprogress()
{
  x=0
  while read i
  do
    x=$[$x + 1]
    if [[ "$x" -eq 25 ]]
    then
      x=0
      echo -n .
    fi
  done
  echo
}

# Set the title bar of the current xterm

set_titlebar()
{
  [ -z "$NO_TITLE_BAR" ] &&
    echo -en "\033]2;$1\007"
}

# Filter out unnecessary noise, keeping just lines starting with "==="

maybe_quiet()
{
  [ -z "$QUIET" ] && cat || grep "^==="
}

# Run a command background if FORK is set, in foreground otherwise

maybe_fork()
{
  if [ -z "$FORK" ]
  then
    eval "$*"
  else
    eval "$*" &
  fi
}

# Kill a process and all its decendants

killtree()
{
  local KIDS=""

  while [ $# -ne 0 ]
  do
    KIDS="$KIDS $(pgrep -P$1)"
    shift
  done

  KIDS="$(echo -n $KIDS)"
  if [ ! -z "$KIDS" ]
  then
    # Depth first kill avoids reparent_to_init hiding stuff.
    killtree $KIDS
    kill $KIDS 2>/dev/null
  fi
}

# Search a colon-separated path for files matching a pattern.

# Arguments are 1) path to search, 2) pattern, 3) command to run on each file.
# During command, $DIR/$FILE points to file found.

path_search()
{
  # For each each $PATH element, loop through each file in that directory,
  # and create a symlink to the wrapper with that name.  In the case of
  # duplicates, keep the first one.

  echo "$1" | sed 's/:/\n/g' | while read DIR
  do
    find "$DIR" -maxdepth 1 -mindepth 1 -name "$2" | sed 's@.*/@@' | \
    while read FILE
    do
      eval "$3"

      # Output is verbose.  Pipe it to dotprogress.

      echo $FILE
    done
  done
}

# Abort if we haven't got a prerequisite in the $PATH

check_prerequisite()
{
  if [ -z "$(which "$1")" ]
  then
    [ -z "$FAIL_QUIET" ] && echo No "$1" in '$PATH'. >&2
    dienow
  fi
}

# Search through all the files under a directory and collapse together
# identical files into hardlinks

collapse_hardlinks()
{
  SHA1LIST=""
  find "$1" -type f | while read FILE
  do
    echo "$FILE"
    SHA1=$(sha1file "$FILE")
    MATCH=$(echo "$SHA1LIST" | grep "^$SHA1")
    if [ -z "$MATCH" ]
    then
      # Yes, the quote spanning two lines here is intentional
      SHA1LIST="$SHA1LIST
$SHA1 $FILE"
    else
      FILE2="$(echo "$MATCH" | sed 's/[^ ]* //')"
      cmp -s "$FILE" "$FILE2" || continue
      ln -f "$FILE" "$FILE2" || dienow
    fi
  done
}
