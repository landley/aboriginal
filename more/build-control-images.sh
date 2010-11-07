#!/bin/bash

# Build all control images (for native-build.sh) in build/control-images.

. sources/include.sh || exit 1

blank_tempdir build/control-images

# Iterate through sources/control-images and run each script, writing output
# to build/control-images/$SCRIPTNAME.hdc

for i in sources/control-images/{*.sh,*/make-control-image.sh}
do
  SCRIPTNAME=$(echo $i | sed 's@sources/control-images/\([^./]*\).*@\1@')
  # Forking doesn't work yet due to extract collisions with the same package
  #maybe_fork "$i build/control-images/$SCRIPTNAME.hdc | maybe_quiet"
  $i build/control-images/$SCRIPTNAME.hdc | maybe_quiet
done
