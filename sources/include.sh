#!/bin/echo "This file is sourced, not run"

# This is the top level include file sourced by each build stage.

# Guard against multiple inclusion

if ! already_included_this 2>/dev/null
then
alias already_included_this=true

# Set up all the environment variables and functions for a build stage.

source config
source sources/utility_functions.sh
source sources/functions.sh
source sources/download_functions.sh
source sources/variables.sh

# Create files with known permissions
umask 022

# Tell bash not to cache the $PATH because we modify it.  (Without this, bash
# won't find new executables added after startup.)
set +h

# Disable internationalization so sort and sed and such can cope with ASCII.

export LC_ALL=C

fi # already_included_this
