#!/bin/echo "This file is sourced, not run"

# Avoid trouble from unexpected environment settings by unsetting all
# environment variables that we don't know about, in case some crazy
# person already exported $CROSS_COMPILE, $ARCH, $CDPATH, or who knows
# what else.  It's hard to know what might drive some package crazy,
# so use a whitelist.

if [ -z "$NO_SANITIZE_ENVIRONMENT" ]
then
  # Which variables are set in config?

  TEMP=$(echo $(sed -n 's/.*export[ \t]*\([^=]*\)=.*/\1/p' config) | sed 's/ /,/g')

  # What other variables should we keep?

  TEMP="$TEMP,LANG,PATH,SHELL,TERM,USER,USERNAME,LOGNAME,PWD,EDITOR,HOME"
  TEMP="$TEMP,DISPLAY,_,TOPSHELL,START_TIME,STAGE_NAME,TOOLCHAIN_PREFIX"
  TEMP="$TEMP,HOST_ARCH,WRAPPY_LOGPATH,OLDPATH,http_proxy,ftp_proxy"
  TEMP="$TEMP,https_proxy,no_proxy,TEMP,TMPDIR,FORK,MUSL"

  # Unset any variable we don't recognize.  It can screw up the build.

  for i in $(env | sed -n 's/=.*//p')
  do
    is_in_list $i "$TEMP" && continue
    [ "${i:0:7}" == "DISTCC_" ] && continue
    [ "${i:0:7}" == "CCACHE_" ] && continue

    unset $i 2>/dev/null
  done
fi

# Assign (export) a variable only if current value is blank

export_if_blank()
{
  [ -z "$(eval "echo \"\${${1/=*/}}\"")" ] && export "$1"
}

# List of fallback mirrors to download package source from

export_if_blank MIRROR_LIST="http://landley.net/code/aboriginal/mirror http://127.0.0.1/code/aboriginal/mirror"

# Where are our working directories?

export_if_blank TOP=`pwd`
export_if_blank SOURCES="$TOP/sources"
export_if_blank SRCDIR="$TOP/packages"
export_if_blank PATCHDIR="$SOURCES/patches"
export_if_blank BUILD="$TOP/build"
export_if_blank SRCTREE="$BUILD/packages"
export_if_blank HOSTTOOLS="$BUILD/host"
export_if_blank WRAPDIR="$BUILD/record-commands"

[ ! -z "$MY_PATCH_DIR" ] && export MY_PATCH_DIR="$(readlink -e "$MY_PATCH_DIR")"

# Set a default non-arch

export WORK="${BUILD}/host-temp"
export ARCH_NAME=host

# What host compiler should we use?

export_if_blank CC=cc

# How many processors should make -j use?

MEMTOTAL="$(awk '/MemTotal:/{print $2}' /proc/meminfo)"
if [ -z "$CPUS" ]
then
  export CPUS=$(echo /sys/devices/system/cpu/cpu[0-9]* | wc -w)
  [ "$CPUS" -lt 1 ] && CPUS=1

  # If we're not using hyper-threading, and there's plenty of memory,
  # use 50% more CPUS than we actually have to keep system busy

  [ -z "$(cat /proc/cpuinfo | grep '^flags' | head -n 1 | grep -w ht)" ] &&
    [ $(($CPUS*512*1024)) -le $MEMTOTAL ] &&
      CPUS=$((($CPUS*3)/2))
fi

export_if_blank STAGE_NAME=`echo $0 | sed 's@.*/\(.*\)\.sh@\1@'`
[ ! -z "$BUILD_VERBOSE" ] && VERBOSITY="V=1"

export_if_blank BUILD_STATIC=busybox,toybox,binutils,gcc-core,gcc-g++,make

# If record-commands.sh set up a wrapper directory, adjust $PATH.

export PATH
if [ -z "$OLDPATH" ]
then
  export OLDPATH="$PATH"
  [ -z "$BUSYBOX" ] || BUSYBOX=busybox
  [ -f "$HOSTTOOLS/${BUSYBOX:-toybox}" ] &&
    PATH="$(hosttools_path)" ||
    PATH="$(hosttools_path):$PATH"

  if [ -f "$WRAPDIR/wrappy" ]
  then
    OLDPATH="$PATH"
    mkdir -p "$BUILD/logs"
    [ $? -ne 0 ] && echo "Bad $WRAPDIR" >&2 && dienow
    PATH="$WRAPDIR"
  fi
fi
export WRAPPY_LOGPATH="$BUILD/logs/cmdlines.$ARCH_NAME.early"
