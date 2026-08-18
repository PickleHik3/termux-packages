TERMUX_PKG_HOMEPAGE=https://github.com/am2rican5/sigye
TERMUX_PKG_DESCRIPTION="A terminal clock with timers, stopwatch and world clock (VAJ: Termux clipboard support)"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="0.6.0"
TERMUX_PKG_REVISION=1
# Pinned to the commit the termux-launcher clipboard patch targets
# (recipes/termux/sigye in PickleHik3/termux-launcher).
_COMMIT=0f0b8caaccb4ca01ab5d1fad1237c4a01a49766f
TERMUX_PKG_SRCURL=https://github.com/am2rican5/sigye/archive/${_COMMIT}.tar.gz
TERMUX_PKG_SHA256=03d21bbb8dbc3ce89bf06ff07f9e1805a0efe8918dd2c8b05f5bbb64b7fbabab
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_BUILD_IN_SRC=true

termux_step_make() {
	termux_setup_rust
	cargo build --jobs $TERMUX_PKG_MAKE_PROCESSES --target $CARGO_TARGET_NAME --locked --release --package sigye
}

termux_step_make_install() {
	install -Dm700 -t $TERMUX_PREFIX/bin target/${CARGO_TARGET_NAME}/release/sigye
}
