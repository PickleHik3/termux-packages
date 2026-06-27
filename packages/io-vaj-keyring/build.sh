TERMUX_PKG_HOMEPAGE=https://github.com/PickleHik3/io-vaj-apt
TERMUX_PKG_DESCRIPTION="GPG public key for the VAJ Terminal package repository"
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_MAINTAINER="VAJ Terminal <archive@pathayam.xyz>"
TERMUX_PKG_VERSION=1.0
TERMUX_PKG_REVISION=1
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_PLATFORM_INDEPENDENT=true
TERMUX_PKG_ESSENTIAL=true

termux_step_make_install() {
	local KEYRING_DIR="$TERMUX_PREFIX/etc/apt/keyrings"

	mkdir -p "$KEYRING_DIR"
	install -Dm644 "$TERMUX_PKG_BUILDER_DIR/io-vaj-archive.gpg" "$KEYRING_DIR/io-vaj-archive.gpg"
}
