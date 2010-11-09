#!/bin/bash

# Build all control images (for native-build.sh) in build/control-images.

. sources/utility_functions.sh || exit 1

blank_tempdir build/control-images

# Iterate through sources/control-images and run each script, writing output
# to build/control-images/$SCRIPTNAME.hdc

for i in sources/control-images/{*.sh,*/make-control-image.sh}
do
  $i | maybe_quiet
  # Forking doesn't work yet due to extract collisions with the same package
  #maybe_fork "$i | maybe_quiet"
done
