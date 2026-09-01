TERMUX_PKG_HOMEPAGE=https://libtorrent.org/
TERMUX_PKG_DESCRIPTION="A feature complete C++ bittorrent implementation focusing on efficiency and scalability"
TERMUX_PKG_LICENSE="BSD 3-Clause"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="2.1.1"
TERMUX_PKG_SRCURL="https://github.com/arvidn/libtorrent/releases/download/v${TERMUX_PKG_VERSION}/libtorrent-rasterbar-${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256=0f163516ecef2e3331500266751de3098835a3c3ae0c2290448046c632bc0e93
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_DEPENDS="boost, libc++, openssl, python"
TERMUX_PKG_BUILD_DEPENDS="boost-headers"
TERMUX_PKG_PYTHON_COMMON_BUILD_DEPS="wheel"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
-DCMAKE_INSTALL_LIBDIR=$TERMUX__PREFIX__LIB_SUBDIR
-DCMAKE_INSTALL_INCLUDEDIR=$TERMUX__PREFIX__INCLUDE_SUBDIR
-Dboost-python-module-name=python
-Dpython-bindings=ON
"

termux_step_pre_configure() {
	# We don't get build-python in path until termux_setup_python_pip is called in
	# termux_step_get_dependencies_python
	TERMUX_PKG_EXTRA_CONFIGURE_ARGS+=" -DPython3_EXECUTABLE=$(command -v build-python)"
}

termux_step_post_make_install() {
	# CMake names the boost-python module after Python3_SOABI, which resolves via the
	# -DPython3_EXECUTABLE build-python above and so now comes out as
	# "libtorrent.cpython-314-x86_64-linux-gnu.so" rather than a bare "libtorrent.so".
	# The tag describes the *host* interpreter that named it, not the object -- the
	# module itself is linked by the NDK toolchain for the target -- so glob for
	# whatever the link step produced and install it under the plain name Python will
	# still import.
	local _module
	_module="$(find "$TERMUX_PKG_BUILDDIR/bindings/python" -maxdepth 1 \
		-name 'libtorrent*.so' -print -quit)"
	[ -n "$_module" ] ||
		termux_error_exit "no libtorrent*.so in $TERMUX_PKG_BUILDDIR/bindings/python"
	install -Dm600 "$_module" "$TERMUX_PYTHON_HOME/site-packages/libtorrent.so"
}
