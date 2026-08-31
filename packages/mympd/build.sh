TERMUX_PKG_HOMEPAGE=https://jcorporation.github.io/myMPD/
TERMUX_PKG_DESCRIPTION="A standalone and lightweight web-based MPD client"
TERMUX_PKG_LICENSE="GPL-3.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="25.3.0"
TERMUX_PKG_SRCURL=https://github.com/jcorporation/myMPD/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=d21170635f5caf7650860bcab23560ec0691acd0102a89a281bbb72ab31a7d01
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_DEPENDS="libflac, libid3tag, lua54, openssl, pcre2, resolv-conf"
# CMakeLists.txt calls find_package(Lua) and then unconditionally overrides the
# result with "set(LUA_LIBRARIES lua5.4)". Upstream assumes one Lua is installed; the
# prefix carries 5.1 through 5.5, so find_package picked 5.5.1 and the build compiled
# against 5.5 headers while linking 5.4 -- hence "undefined symbol:
# luaL_openselectedlibs", which exists in lua5.5's lualib.h and not in lua5.4's. Pin
# the headers to the version actually being linked, which also stops the outcome
# depending on which lua packages happen to be present. LUA_MIN_VERSION is 5.4.0, so
# 5.4 still satisfies the version gate.
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
-DMATH_LIB=m
-DMYMPD_STARTUP_SCRIPT=OFF
-DLUA_INCLUDE_DIR=$TERMUX_PREFIX/include/lua5.4
-DLUA_LIBRARY=$TERMUX_PREFIX/lib/liblua5.4.so
"
