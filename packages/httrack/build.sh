TERMUX_PKG_HOMEPAGE=http://www.httrack.com
TERMUX_PKG_DESCRIPTION="It allows you to download a World Wide Web site from the Internet"
TERMUX_PKG_LICENSE="GPL-3.0"
TERMUX_PKG_MAINTAINER="@termux"
# Debian expires old versions out of the pool, and 3.49.15 is gone: the recipe's
# URL now 404s, and so does archive.debian.org and httrack's own historical mirror.
# The pool currently carries 3.49.2/4/6/23/25 and 3.50.0, so there is no way to
# build the pinned version at all. Bumped to the newest one present; the tarball was
# checked to be real httrack source (AC_INIT([httrack], [3.50.0], ...)) rather than
# an error page before this hash was taken.
TERMUX_PKG_VERSION="3.50.0"
TERMUX_PKG_REVISION=1
TERMUX_PKG_SRCURL=https://ftp.debian.org/debian/pool/main/h/httrack/httrack_${TERMUX_PKG_VERSION}.orig.tar.gz
TERMUX_PKG_SHA256=9511ebf352eb0b6fb958afafaaf29eb76736440eaf9746006b03e38b1335503e
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_DEPENDS="httrack-data, libandroid-execinfo, libandroid-spawn, libiconv, openssl, zlib"
TERMUX_PKG_BREAKS="httrack-dev"
TERMUX_PKG_REPLACES="httrack-dev"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
--docdir=$TERMUX_PREFIX/share/httrack/html
--with-zlib=$TERMUX_PREFIX
LIBS=-liconv
"
TERMUX_PKG_BUILD_IN_SRC=true

termux_step_pre_configure() {
	# Prevent warnings as error
	sed -i "s/-Werror/-Wno-error/g" configure.ac
	autoreconf -fiv

	# 3.50.0 spawns the external catchurl helper with posix_spawnp; bionic has no
	# posix_spawn, so the link fails on posix_spawnp and
	# posix_spawn_file_actions_adddup2 without Termux's shim.
	LDFLAGS+=" -landroid-spawn"
}

termux_step_post_configure() {
	make clean
}
