#!/bin/bash

# Download all the source tarballs we haven't got up-to-date copies of.

URL=http://zlib.net/zlib-1.2.5.tar.bz2 \
SHA1=543fa9abff0442edca308772d6cef85557677e02 \
maybe_fork "download || dienow"

URL=http://ftp.gnu.org/pub/gnu/ncurses/ncurses-5.7.tar.gz \
SHA1=8233ee56ed84ae05421e4e6d6db6c1fe72ee6797 \
maybe_fork "download || dienow"

URL=http://python.org/ftp/python/2.6.5/Python-2.6.5.tar.bz2 \
SHA1=24c94f5428a8c94c9d0b316e3019fee721fdb5d1 \
RENAME='s/P/p/' \
maybe_fork "download || dienow"

URL=http://ftp.gnu.org/gnu/bash/bash-3.2.tar.gz \
SHA1=fe6466c7ee98061e044dae0347ca5d1a8eab4a0d \
maybe_fork "download || dienow"

URL=http://www.samba.org/ftp/rsync/src/rsync-3.0.7.tar.gz \
SHA1=63426a1bc71991d93159cd522521fbacdafb7a61 \
maybe_fork "download || dienow"

URL=http://ftp.gnu.org/gnu/patch/patch-2.5.9.tar.gz \
SHA1=9a69f7191576549255f046487da420989d2834a6 \
maybe_fork "download || dienow"

URL=ftp://ftp.astron.com/pub/file/file-5.03.tar.gz \
SHA1=f659a4e1fa96fbdc99c924ea8e2dc07319f046c1 \
maybe_fork "download || dienow"

URL=http://dev.gentoo.org/~zmedico/portage/archives/portage-2.1.8.tar.bz2 \
SHA1=390c97f3783af2d9e52482747ead3681655ea9c3 \
maybe_fork "download || dienow"
