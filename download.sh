#!/bin/sh

export SRCDIR=sources/packages
export STAGE2SRC=../packages
mkdir -p "$SRCDIR"

function download()
{
  FILENAME=`echo "$URL" | sed 's .*/  '`
  BASENAME=`echo "$FILENAME" | sed -r -e 's/-*([0-9\.]|-rc)*(\.tar\..z2*)$/\2/'`

  if [ ! -z "$STAGEDIR" ]
  then
    rm -f "$STAGEDIR/$BASENAME" 2> /dev/null
    ln -s "$STAGE2SRC/$FILENAME" "$STAGEDIR/$BASENAME"
  fi

  # The extra "" is so we test the sha1sum after the last download.

  for i in "$URL" http://www.landley.net/code/firmware/mirror/"$FILENAME" ""
  do
    # Return success if we have a valid copy of the file

    # Test first (so we don't re-download a file we've already got).

    SUM=`cat "$SRCDIR/$FILENAME" | sha1sum | awk '{print $1}'`
    if [ x"$SUM" == x"$SHA1" ]
    then
      touch "$SRCDIR/$FILENAME"
      echo "Confirmed $FILENAME"
      return 0
    fi

    # If there's a corrupted file, delete it.  In theory it would be nice
    # to resume downloads, but wget creates "*.1" files instead.

    rm "$SRCDIR/$FILENAME" 2> /dev/null

    # If we have another source, try to download file.

    if [ -n "$i" ]
    then
      wget -P "$SRCDIR" "$i"
    fi
  done

  # Return failure.

  echo "Could not download $FILENAME"
  return 1
}

# Lots and lots of source code.  Download everything we haven't already got
# a copy of.

echo "=== Download source code." &&

export SRCDIR=sources/packages
mkdir -p "$SRCDIR"

# Required for cross compile toolchain

export STAGEDIR=sources/build-cross
mkdir -p "$STAGEDIR"

URL=http://www.kernel.org/pub/linux/kernel/v2.6/linux-2.6.19.tar.bz2 \
SHA1=c00d5891e2461bce45be51c1ef7846ee842792dd \
download &&

URL=http://www.uclibc.org/downloads/snapshots/uClibc-20061128.tar.bz2 \
SHA1=50c024ac137262981348ad54e0f64d83db1bce4e \
download &&

URL=ftp://ftp.gnu.org/gnu/binutils/binutils-2.17.tar.bz2 \
SHA1=a557686eef68362ea31a3aa41ce274e3eeae1ef0 \
download &&

URL=ftp://ftp.gnu.org/gnu/gcc/gcc-4.1.1/gcc-core-4.1.1.tar.bz2 \
SHA1=147e12bf96a8d857fda1d43f0d7ea599b89cebf9 \
download &&

# Required for native build environment

export STAGEDIR=sources/build-native
mkdir -p "$STAGEDIR"

URL=http://superb-east.dl.sourceforge.net/sourceforge/squashfs/squashfs3.1.tar.gz \
SHA1=89d537fd18190402ff226ff885ddbc14f6227a9b \
download &&

URL=http://www.busybox.net/downloads/busybox-1.2.2.tar.bz2 \
SHA1=59670600121c9dacfd61e72e34f4bd975ec2c36f \
download &&

URL=ftp://ftp.gnu.org/gnu/make/make-3.81.tar.bz2 \
SHA1=41ed86d941b9c8025aee45db56c0283169dcab3d \
download &&

echo === Got all source.
