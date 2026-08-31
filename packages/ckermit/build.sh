TERMUX_PKG_HOMEPAGE=https://www.kermitproject.org/ckermit.html
TERMUX_PKG_DESCRIPTION="A combined network and serial communication software package"
TERMUX_PKG_LICENSE="BSD 3-Clause"
TERMUX_PKG_LICENSE_FILE="COPYING.TXT"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=9.0.302
TERMUX_PKG_REVISION=4
TERMUX_PKG_SRCURL=https://www.kermitproject.org/ftp/kermit/archives/cku${TERMUX_PKG_VERSION##*.}.tar.gz
TERMUX_PKG_SHA256=0d5f2cd12bdab9401b4c836854ebbf241675051875557783c332a6a40dac0711
TERMUX_PKG_DEPENDS="libcrypt"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_EXTRA_MAKE_ARGS="-e linuxa"

termux_extract_src_archive() {
	local file="$TERMUX_PKG_CACHEDIR/$(basename "${TERMUX_PKG_SRCURL}")"
	mkdir -p "$TERMUX_PKG_SRCDIR"
	tar xf "$file" -C "$TERMUX_PKG_SRCDIR" --strip-components=0
}

termux_step_pre_configure() {
	CFLAGS+=" -fPIC -Wno-error=implicit-int"
	# ckwart -- the host-side "wart" preprocessor -- is built by the makefile with
	# $(CC_FOR_BUILD), which never sees the CFLAGS above. Its K&R definitions, e.g.
	# "main(argc,argv) int argc; char **argv; {", now fail as "return type defaults
	# to 'int' [-Wimplicit-int]". Note -std=gnu17 does NOT help: current gcc raises
	# implicit-int to an error whatever the standard, so it has to be downgraded by
	# name, exactly as CFLAGS above does for the target compiler.
	export CC_FOR_BUILD="$CC_FOR_BUILD -Wno-error=implicit-int"
	export KFLAGS="-DNOGETUSERSHELL -UNOTIMEH -DTIMEH -DUSE_FILE_R"
	LDFLAGS+=" -lcrypt"
	export LNKFLAGS="$LDFLAGS"
}

termux_step_make_install() {
	mkdir -p $TERMUX_PREFIX/bin
	mkdir -p $TERMUX_PREFIX/share/man
	make prefix=$TERMUX_PREFIX manroot=$TERMUX_PREFIX/share install
	install -Dm600 -t $TERMUX_PREFIX/share/doc/ckermit/ *.txt
}
