#!/bin/bash

. sources/functions.sh || exit 1

# This script compiles stuff under the final system, using distcc to call out
# to the cross compiler.

# Set up a timeout.  If it doesn't complete in 60 seconds, it failed.

timeout()
{
  sleep 45
  kill $1
}

timeout $$ &
trap "killtree $$" EXIT

# Call run-from-build with a here document to do stuff.

# Note that the first line of the script is a few spaces followed by a comment
# character.  This gives some harmless data for the linux boot process to
# consume and discard before it gets to the command prompt.  I don't know why
# it does this, but it does.  The comment character is so you can see how
# much got eaten, generally about 3 characters.

# If you cat your own script into emulator-build.sh, you probably also need
# to start with a line of spaces like that.  Just FYI.

./run-from-build.sh $1 << 'EOF'
          #
# Show free space
df
# Smoke test for the compiler
gcc -s /usr/src/thread-hello2.c -lpthread -o /tmp/hello &&
/tmp/hello
sync
exit
EOF
