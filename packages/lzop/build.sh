TERMUX_PKG_HOMEPAGE=https://www.lzop.org
TERMUX_PKG_DESCRIPTION='File compressor using lzo lib.'
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=1.04
TERMUX_PKG_REVISION=2
# VAJ: fossies.org (a third-party mirror) no longer serves this. lzop.org is the
# project's own site and only publishes .tar.gz, so URL and checksum move together.
TERMUX_PKG_SRCURL=https://www.lzop.org/download/lzop-$TERMUX_PKG_VERSION.tar.gz
TERMUX_PKG_SHA256=7e72b62a8a60aff5200a047eea0773a8fb205caf7acbe1774d95147f305a2f41
TERMUX_PKG_DEPENDS="liblzo"
