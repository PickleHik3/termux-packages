TERMUX_PKG_HOMEPAGE=https://github.com/e2tools/e2tools
TERMUX_PKG_DESCRIPTION="mtools analogue for ext2/3 filesystems"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="0.1.2"
TERMUX_PKG_REVISION=1
TERMUX_PKG_SRCURL=https://github.com/e2tools/e2tools/releases/download/v$TERMUX_PKG_VERSION/e2tools-$TERMUX_PKG_VERSION.tar.gz
TERMUX_PKG_SHA256=b19593bbfc85e9c14c0d2bc8525887901c8fe02588c76df60ab843bf0573c4a2
TERMUX_PKG_DEPENDS="e2fsprogs"
TERMUX_PKG_AUTO_UPDATE=true

termux_step_pre_configure() {
	# krb5 installs its own libcom_err.so, so com_err.pc's -lcom_err resolves to MIT's
	# implementation rather than e2fsprogs's libcom_err.a -- and MIT's does not define
	# the _et_list that e2fsprogs's libext2fs.a needs. Pin the e2fsprogs archive, and
	# keep include/et ahead of include/ so et/com_err.h wins over krb5's com_err.h.
	# configure.ac uses PKG_CHECK_MODULES, which honours these if already set.
	export COM_ERR_CFLAGS="-I${TERMUX_PREFIX}/include/et -I${TERMUX_PREFIX}/include"
	export COM_ERR_LIBS="-L${TERMUX_PREFIX}/lib -l:libcom_err.a"
}
