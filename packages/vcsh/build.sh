TERMUX_PKG_HOMEPAGE=https://github.com/RichiH/vcsh
TERMUX_PKG_DESCRIPTION="Config manager based on Git"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="2.0.10"
TERMUX_PKG_SRCURL=https://github.com/RichiH/vcsh/releases/download/v${TERMUX_PKG_VERSION}/vcsh-${TERMUX_PKG_VERSION}.tar.zst
TERMUX_PKG_SHA256=6ed8f4eee683f2cc8f885b31196fdc3b333f86ebc3110ecd1bcd60dfac64c0b4
TERMUX_PKG_DEPENDS="git"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_PLATFORM_INDEPENDENT=true
TERMUX_PKG_AUTO_UPDATE=true

termux_step_post_configure() {
	# AX_AM_MACROS rewrites aminclude.am from configure, and Makefile.in lists it as a
	# prerequisite, so after configure the shipped Makefile.in always looks stale. That
	# fires automake's maintainer rule, which runs build-aux/missing automake-1.16 --
	# a version the builder does not have. The generated files are fine as shipped, so
	# just restamp them past aminclude.am.
	touch Makefile.in
	touch Makefile
}
