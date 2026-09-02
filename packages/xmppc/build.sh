TERMUX_PKG_HOMEPAGE=https://codeberg.org/Anoxinon_e.V./xmppc
TERMUX_PKG_DESCRIPTION="Command Line Interface Tool for XMPP"
TERMUX_PKG_LICENSE="GPL-3.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=0.1.2
TERMUX_PKG_REVISION=4
# Codeberg generates archive tarballs on demand, and for this repository that
# endpoint now answers 504 -- three 180s attempts returned the same 92-byte error
# page, and it was already failing a day earlier, so it is not a blip. The repository
# itself is fine (the project page is 200 and git ls-remote lists every tag), so clone
# the tag instead of fetching a generated tarball. This also removes the standing
# hazard that a forge which regenerates archives can change their bytes, and with
# them a pinned checksum, without the release changing at all.
#
# git+ sources skip TERMUX_PKG_SHA256 (lint expects it unset), so integrity comes from
# asserting the commit the tag resolves to, below.
TERMUX_PKG_SRCURL=git+https://codeberg.org/Anoxinon_e.V./xmppc
TERMUX_PKG_GIT_BRANCH=${TERMUX_PKG_VERSION}
TERMUX_PKG_DEPENDS="libstrophe, glib, gpgme"

_COMMIT=b1b3f62def7963face0e4928e4167ef1301feaa3

termux_step_post_get_source() {
	local commit
	commit="$(git rev-parse HEAD)"
	if [ "$commit" != "$_COMMIT" ]; then
		termux_error_exit "Expected tag $TERMUX_PKG_VERSION at $_COMMIT, got $commit."
	fi
}

termux_step_pre_configure() {
	./bootstrap.sh
}
