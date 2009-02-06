# leftover things that buildall.sh doesn't do yet.

exit 1

# USE_STATIC_HOST=i686

# Create and upload readme (requires build/sources to be extracted)

(do_readme && cat sources/toys/README.footer) | tee buildall/README &

# If we need to create static cross compilers, build a version of mini-native
# to act as the host system.  (That way they're statically linked against
# uClibc, not whatever the host's library is.)

if [ ! -z "$USE_STATIC_HOST" ]
then
  ($NICE ./build.sh "$USE_STATIC_HOST" || dienow) |
    tee >(bzip2 > buildall/logs/static-host-$USE_STATIC_HOST.txt.bz2)

# Feed a script into qemu.  Pass data back and forth via netcat.
# This intentionally _doesn't_ use $NICE, so the distcc master node is higher
# priority than the distccd slave nodes.

./run-from-build.sh "$USE_STATIC_HOST" << EOF
          #
export USE_UNSTABLE=$USE_UNSTABLE
export CROSS_BUILD_STATIC=1
cd /home &&
netcat 10.0.2.2 $(build/host/netcat -s 127.0.0.1 -l hg archive -t tgz -) | tar xvz &&
cd firmware-* &&
netcat 10.0.2.2 $(build/host/netcat -s 127.0.0.1 -l tar c sources/packages) | tar xv &&
./download.sh --extract &&
mkdir -p build/logs || exit 1
for i in $(cd sources/targets; ls)
do
  ./cross-compiler.sh \$i | tee build/logs/cross-static-\$i.txt
  bzip2 build/logs/cross-static-\$i.txt
done
cd build
tar c logs/* cross-compiler-*.tar.bz2 | netcat 10.0.2.2 \
  $(cd buildall; ../build/host/netcat -s 127.0.0.1 -l tar xv)
sync
exit
EOF

  # Extract the cross compilers

  for i in buildall/cross-compiler-*.tar.bz2
  do
    echo Extracting $i
    tar -xj -f $i -C build || dienow
  done
fi
