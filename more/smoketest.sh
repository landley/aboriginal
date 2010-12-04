#!/bin/bash

# This script compiles stuff under the final system, using distcc to call out
# to the cross compiler.  It calls run-from-build with a here document.

# Note that the first line of the script is a few spaces followed by a comment
# character.  This gives some harmless data for the linux boot process (serial
# initialization) to consume and discard before it gets to the command prompt.
# (The comment character is just so you can see how much got eaten.)

# If you cat your own script into emulator-build.sh, you probably also need
# to start with a line of spaces like that.  Just FYI.

more/timeout.sh 60 more/run-emulator-from-build.sh "$1" << 'EOF'
          #
# Show free space
df
# Smoke test for the compiler
gcc -s /usr/src/thread-hello2.c -lpthread -o /tmp/hello &&
/tmp/hello
sync
exit
EOF
