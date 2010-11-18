#!/bin/sh

sed -i '/MV.*old/d' Makefile.in &&
sed -i '/{OLDSUFF}/c:' support/shlib-install &&
./configure --prefix=/usr --libdir=/lib &&
make -j $CPUS SHLIB_LIBS=-lncurses &&
make install  || exit 1

if [ ! -z "$DOCS" ]
then
  mkdir /usr/share/doc/readline &&
  install -m644 doc/*.ps doc/*.pdf doc/*.html doc/*.dvi \
    /usr/share/doc/readline || exit 1
fi

cat > /etc/inputrc << "EOF"
# Allow the command prompt to wrap to the next line
set horizontal-scroll-mode Off

# Enable 8bit input
set meta-flag On
set input-meta On

# Turns off 8th bit stripping
set convert-meta Off

# Keep the 8th bit for display
set output-meta On

# none, visible or audible
set bell-style none

# All of the following map the escape sequence of the value
# contained in the 1st argument to the readline specific functions
"\eOd": backward-word
"\eOc": forward-word

# for linux console
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[5~": beginning-of-history
"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert

# for xterm
"\eOH": beginning-of-line
"\eOF": end-of-line

# for Konsole
"\e[H": beginning-of-line
"\e[F": end-of-line
EOF
