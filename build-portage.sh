#!/tools/bin/bash -x

## This is based on the first part of the LFS manual, in regards to
## the files that would reside in /tools. The three exceptions are 
## wget, Python, and Perl is compiled fully.

## Also, currently the script does not deal with
## determing if there exist /etc/resolv.conf, so I leave that
## up to you.

## The initial meat for this was found at 
## http://dev.gentoo.org/~vapier/bootstrap-portage, but
## has been heavily modified due to doing "UNINTENDED THINGS"
## That and the developer making that script intended it
## to be installed on an already functioning system not
## shifted to /tools, and well, yah.

## NOTE ON PATHS: It's assumed /bin:/usr/bin:/sbin ... /tools/bin are
## already set for the PATH variable.

# Version of Portage
PV=2.1.2

# CFLAGS, CHOST, ACCEPT_KEYWORDS, ARCH
# NOTE: These are where you can change the processor
# architecture you want to build for. There's also the 
# make.profile that needs to be set later on, based on 
# ACCEPT_KEYWORDS. (ACCEPT_KEYWORDS functions based on 
# architecture. For example, an x86 install would just be x86, 
# PowerPC would be ppc, et cetera.

# They're hardcoded right now, but you get the idea
ACCEPT_KEYWORDS="x86"
ARCH="x86"
CFLAGS="-march=i686 -O2 -pipe"
CHOST="i386-pc-linux-gnu"

# We need an initial directory structure to make things easier on us
# Feel free to clean this up. This has been hand-added as portage borks
# on me wanting a directory NOTE: This is assuming /etc exists, as 
# noted above

# NOTE: There exist the sys-apps/baselayout ebuild. Perhaps this would
# be a nice thing to parse initially. Until then, ugly hack!

mkdir /bin
mkdir -p /usr/bin
mkdir /usr/sbin
mkdir -p /var/log
mkdir /var/tmp
mkdir /tmp

# We also need an ugly hack right now, in order to utilize hard-coded
# paths by the Gentoo scripts. Luckily, by using symlinks with /tools
# prefix, it makes it easy to go in later and remove everything
# portage didn't install, and it's only the /bin directory
ln -s /tools/bin/* /bin/
ln -s /tools/bin/* /usr/bin/
# Why both? It wants python in /usr/bin. Let's just be safe in case
# it wants others

### ****WARNING******
### The following is because I used a different script to bootstrap Python,
### not the LFS way (bootstrap-prefix.sh from the Prefix-Portage files)
### So take this out if you built it with LFS
ln -s /bootstrap/usr/bin/python /usr/bin/

# Now on to bootstrapping portage. Much hardcoded stuff, 
# but I was on intent on just getting it "to work"

# It would also be nice to implement a way to grab the portage ebuild
# file and just parse that, to ensure we're not missing any new additions
# But this is what I have now.

A=portage-${PV}.tar.bz2
S=/var/tmp/portage-${PV}

wget -P /var/tmp http://gentoo.osuosl.org/distfiles/${A}
cd /var/tmp
tar -jxf ${A}

python -O -c "import compileall; compileall.compile_dir('${S}/pym')"
cd ${S}/src; gcc ${CFLAGS} tbz2tool.c -o tbz2tool 

# There also exists a make.conf in this directory, but it's insanely
# long, and we already know what we want to put in it initially
cd ${S}/cnf; cp etc-update.conf dispatch-conf.conf make.globals /etc/

# Inserts the Python modules for portage
mkdir -p /usr/lib/portage/pym
cd ${S}/pym
cp -r * /usr/lib/portage/pym/

mkdir -p /usr/lib/portage/bin
cd ${S}/bin
cp * ${S}/src/tbz2tool /usr/lib/portage/bin

# Get some standard symlinks for portage apps

for x in ebuild emerge portageq repoman tbz2tool xpak; 
do
	ln -s ../lib/portage/bin/${x} /usr/bin/${x}
done

for x in archive-conf dispatch-conf emaint emerge-webrsync \
	env-update etc-update fixpackages quickpkg regenworld
do
	ln -s ../lib/portage/bin/${x} /usr/sbin/${x}
done

# Go ahead and create this for later
mkdir -p /etc/portage

# Get rid of pesky error messages for the first run
touch /var/log/emerge.log

# Ugly, Ugly, Ugly. But this works until I can put this into a Mercurial 
# repository. A really nice thing to do, as noted before, is process
# the baselayout ebuild which would take care of all this for us.
wget -O /etc/group http://sources.gentoo.org/viewcvs.py/*checkout*/baselayout/trunk/etc/group?rev=2072
wget -O /etc/passwd http://sources.gentoo.org/viewcvs.py/*checkout*/baselayout/trunk/etc/passwd?rev=2072

# make.conf and make.profile should probably be set now
echo ACCEPT_KEYWORDS='"'$ACCEPT_KEYWORDS'"' >> /etc/make.conf
echo CHOST='"'$CHOST'"' >> /etc/make.conf
echo CFLAGS='"'$CFLAGS'"' >> /etc/make.conf
# Don't want mouse support now. It makes nasty cyclical dependencies in the
# beginning. Also don't want ssl with wget. These will be removed once we
# have enough to recompile the system
echo 'USE="-gpm -ssl"' >> /etc/make.conf

# Now we need a Portage Snapshot

# It became annoying to constantly redownload this in rerunning the script.
# This script is a mess now, though. But that's to be expected
if [ ! -e "/var/tmp/portage-latest.tar.bz2" ] ; then
	wget -P /var/tmp http://gentoo.osuosl.org/snapshots/portage-latest.tar.bz2
fi
cd /usr
tar -jxf /var/tmp/portage-latest.tar.bz2

# Now we can set a make.profile
ln -s /usr/portage/profiles/default-linux/${ARCH}/2006.1/desktop /etc/make.profile

# And now we have portage. Let's do things with it
# This was taken from:
# http://www.gentoo.org/proj/en/gentoo-alt/prefix/bootstrap-macos.xml
# and was the basis for the Prefix-Portage script I wrote. It's being
# altered as I try to emerge something, fail, look at errors, rinse/repeat.

# Setting up some environment variables
export LD_LIBRARY_PATH="/usr/lib:/lib"

# It wants scanelf. I don't know why. pax-utils has it, make it happy.
emerge --oneshot pax-utils
emerge --oneshot sed
# bash wants yacc. The FSF should be sued.
emerge --oneshot yacc
emerge --oneshot bash

# Automake
emerge --oneshot --nodeps "=autoconf-2.1*" "=autoconf-2.6*" "autoconf-wrapper"
emerge --oneshot --nodeps "=autoconf-2.1*" "=autoconf-2.6*" "autoconf-wrapper"
emerge --oneshot --nodeps "=automake-1.4*" "=automake-1.5*" \
	"=automake-1.6*" "=automake-1.7*" "=automake-1.8*" \ 
	"automake-wrapper"

emerge --oneshot --nodeps wget
emerge --oneshot --nodeps sys-apps/texinfo
emerge --oneshot --nodeps "=automake-1.9*" "=automake-1.10*"
emerge --oneshot --nodeps libtool
emerge --oneshot --nodeps sys-apps/coreutils
emerge --oneshot gawk
# emerge --oneshot --nodeps python
env FEATURES="-collision-protect" emerge --oneshot --nodeps portage
emerge --oneshot --nodeps baselayout
emerge -e system
