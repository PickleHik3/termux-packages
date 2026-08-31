TERMUX_PKG_HOMEPAGE=https://git.zx2c4.com/music-file-organizer/about/
TERMUX_PKG_DESCRIPTION="Organizer of audio files into directories based on metadata tags"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=1.0.4
TERMUX_PKG_REVISION=10
TERMUX_PKG_SRCURL=https://git.zx2c4.com/music-file-organizer/snapshot/music-file-organizer-$TERMUX_PKG_VERSION.tar.xz
# cgit generates these snapshots on demand and its xz output is not reproducible
# across server upgrades, so this checksum rots even though the tag never moves.
# Verified before re-pinning: the tarball's contents are byte-identical to the 1.0.4
# tag (commit 51755459acd2c32b2b9b64b3673160cd2d4edef1, dated 2023-07-31).
TERMUX_PKG_SHA256=a379cea1fe6381b5bface27deeb7e4db1f76b2fb2230dadc1f171b796e9a43d7
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_DEPENDS="libicu, taglib"
