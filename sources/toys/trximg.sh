#!/bin/bash

# Create a TRX image from up to three source files (kernel, initramfs, rootfs),
# and output it to stdout.  (This is the format you flash linksys routers with.)

# The TRX format is a simple (28 byte) header followed by the concatenation of
# the files with each file zero padded to a multiple of 4 bytes, and then the
# file as a whole padded up to 4k.  Padding is done with zero bytes.

# The tricky part is calculating the lengths and CRC for the header before
# outputting the header, without screwing up the ability to pipe the output
# somewhere.

if [ ! -f "$1" ] ||
   ( [ ! -z "$2" ] && [ ! -f "$2" ] ) ||
   ( [ ! -z "$3" ] && [ ! -f "$3" ] )
then
  echo "Usage: trximg.sh file1 [file2 [file3]]" >&2
  exit 1
fi

# Output $1 bytes of decimal number $2 as little endian binary data

function leout()
{
  X=0
  DATA=$2

  # Loop through bytes, smallest first

  while [ $X -lt $1 ]
  do
    # Grab next byte

    BYTE=$[$DATA%256]
    DATA=$[$DATA/256]

    # Convert to octal (because that's what echo needs)

    OCTAL=""
    for i in 1 2 3
    do
      OCTAL=$[$BYTE%8]"$OCTAL"
      BYTE=$[$BYTE/8]
    done

    # Emit byte and loop

    echo -ne "\0$OCTAL"

    X=$[$X+1]
    BYTE=$x
  done
}

# Print number of bytes required to round $2 up to a multiple of $1

function padlen()
{
  echo $[($1-($2%$1))%$1]
}

# Print number $2 rounded up to $1

function roundlen()
{
  echo $[$2+$(padlen $1 $2)]
}

# Return length of file $1 in bytes

function filelen()
{
  wc -c "$1" | awk '{print $1}'
}

# Output $1 zero bytes

function zpad()
{
  [ $1 -ne 0 ] && dd if=/dev/zero bs=$1 count=1 2>/dev/null
}

# Output file $2, followed by enough zero bytes to pad length up to $1 bytes

function zpad_file()
{
  [ -z "$2" ] && return
  cat $2
  zpad $(padlen $1 $(filelen "$2"))
}

# Output header.  (Optionally just the part included in the CRC32).

function emit_header
{
  if [ -z "$1" ]
  then
    echo -n "HDR0"       # File ID magic
    leout 4 $LENGTH      # Length of file (including this header)
    leout 4 $CRC32       # crc32 of all file data after this crc field
  fi

  leout 2 0            # flags
  leout 2 1            # version
  leout 4 28           # Start of first file
  leout 4 $OFFSET2     # Start of second file
  leout 4 $OFFSET3     # Start of third file
}

# Calculate file offsets for the three arguments

TOTAL=$[28+$(roundlen 4 $(filelen "$1"))]
if [ -z "$2" ]
then
  OFFSET2=0
else
  OFFSET2=$TOTAL
  TOTAL=$[$TOTAL+$(roundlen 4 $(filelen "$2"))]
fi
if [ -z "$3" ]
then
  OFFSET3=0
else
  OFFSET3=$TOTAL
  TOTAL=$[$TOTAL+$(roundlen 4 $(filelen "$3"))]
fi
LENGTH=$(roundlen 4096 $TOTAL)

# Calculate the CRC value for the header

CRC32=$(
  (
   emit_header skip
   zpad_file 4 "$1"
   zpad_file 4 "$2"
   zpad_file 4 "$2"
  ) | cksum
)

# Output the image to stdout

emit_header
zpad_file 4 "$1"
zpad_file 4 "$2"
zpad_file 4 "$3"
zpad $(padlen 4096 $TOTAL)
