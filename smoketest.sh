#!/bin/bash

# This script compiles stuff under the final system, using distcc to call out
# to the cross compiler.

# Note that the first line of the script is a few spaces followed by a comment
# character.  This gives some harmless data for the linux boot process to
# consume and discard before it gets to the command prompt.  I don't know why
# it does this, but it does.  The comment character is so you can see how
# much got eaten, generally about 3 characters.

# If you cat your own script into emulator-build.sh, you probably also need
# to start with a line of spaces like that.  Just FYI.

./emulator-build.sh $1 << 'EOF'
          #
# Show free space
df
# Smoke test for the compiler
gcc -s /tools/src/thread-hello2.c -lpthread &&
./a.out
sync
exit
EOF
