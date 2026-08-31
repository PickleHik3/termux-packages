TERMUX_PKG_HOMEPAGE=https://luvit.io
TERMUX_PKG_DESCRIPTION="Toolkit for developing, sharing, and running luvit/lua programs and libraries."
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=3.8.5
TERMUX_PKG_REVISION=3
TERMUX_PKG_SRCURL=git+https://github.com/luvit/lit.git
TERMUX_PKG_GIT_BRANCH=${TERMUX_PKG_VERSION}
TERMUX_PKG_DEPENDS="luvi"
TERMUX_PKG_SUGGESTS="luvit"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_NO_STRIP=true

# The prebuilt host luvi these steps run completes its work, prints "done: success",
# and then aborts while tearing down (SIGABRT, exit 134). Judge the invocations by
# the artifact they produce rather than by their exit status, and still refuse any
# other failure. The unzip in termux_step_make_install is the integrity check.
_lit_run() {
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
	_lit_run lit sh "${TERMUX_PKG_SRCDIR}/get-lit.sh"
	mv lit "${TERMUX_PKG_SRCDIR}/_lit"
}

termux_step_make() {
	touch dummy
	_lit_run lit ./_lit make . ./lit dummy
}

termux_step_make_install() {
	mkdir -p "${TERMUX_PREFIX}/share/lit"
	unzip -d "${TERMUX_PREFIX}/share/lit" lit

	cat > "${TERMUX_PREFIX}/bin/lit" <<-EOF
	#!${TERMUX_PREFIX}/bin/env bash
	exec luvi ${TERMUX_PREFIX}/share/lit -- \$@
	EOF
	chmod 700 "${TERMUX_PREFIX}/bin/lit"
}
