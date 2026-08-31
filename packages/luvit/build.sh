TERMUX_PKG_HOMEPAGE=https://luvit.io
TERMUX_PKG_DESCRIPTION="Asynchronous I/O for Lua"
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=2.18.1
TERMUX_PKG_REVISION=1
TERMUX_PKG_SRCURL=https://github.com/luvit/luvit/archive/refs/tags/${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=b792781d77028edb7e5761e96618c96162bd68747b8fced9a6fc52f123837c2c
TERMUX_PKG_DEPENDS="luvi"
TERMUX_PKG_SUGGESTS="lit"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_NO_STRIP=true

# The prebuilt host luvi these steps run completes its work, prints "done: success",
# and then aborts while tearing down (SIGABRT, exit 134). Judge the invocations by
# the artifact they produce rather than by their exit status, and still refuse any
# other failure. The unzip in termux_step_make_install is the integrity check.
_luvit_lit_run() {
	local artifact="$1"
	shift
	local rc=0
	"$@" || rc=$?
	[ -s "$artifact" ] ||
		termux_error_exit "'$*' produced no $artifact (exit $rc)"
	[ "$rc" = 0 ] || [ "$rc" = 134 ] ||
		termux_error_exit "'$*' failed with exit $rc"
}

termux_step_configure() {
	local _lit_url="https://github.com/luvit/lit/raw/$(
		source "${TERMUX_SCRIPTDIR}/packages/lit/build.sh"
		echo "${TERMUX_PKG_VERSION}"
	)/get-lit.sh"
	curl -Lo get-lit.sh "$_lit_url"
	_luvit_lit_run lit sh ./get-lit.sh
	mv lit "${TERMUX_PKG_SRCDIR}/_lit"
}

termux_step_make() {
	touch dummy
	_luvit_lit_run luvit ./_lit make . ./luvit dummy
}

termux_step_make_install() {
	mkdir -p "${TERMUX_PREFIX}/share/luvit"
	unzip -d "${TERMUX_PREFIX}/share/luvit" luvit

	cat > "${TERMUX_PREFIX}/bin/luvit" <<-EOF
	#!${TERMUX_PREFIX}/bin/env bash
	exec luvi ${TERMUX_PREFIX}/share/luvit -- \$@
	EOF
	chmod 700 "${TERMUX_PREFIX}/bin/luvit"
}
