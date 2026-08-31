TERMUX_PKG_HOMEPAGE=https://www.openexr.com/
TERMUX_PKG_DESCRIPTION="Provides the specification and reference implementation of the EXR file format"
TERMUX_PKG_LICENSE="BSD 3-Clause"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="3.4.4"
TERMUX_PKG_REVISION=2
TERMUX_PKG_SRCURL="https://github.com/AcademySoftwareFoundation/openexr/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256=7c663c3c41da9354b5af277bc2fd1d2360788050b4e0751a32bcd50e8abaef8f
# libOpenEXRCore has NEEDED libdeflate.so, and the installed OpenEXRConfig.cmake
# does find_dependency(libdeflate) -- without it every CONFIG-mode consumer of
# OpenEXR silently fails to find the package (libvigra).
TERMUX_PKG_DEPENDS="imath, libc++, libdeflate, zlib"
# libdeflate's CMake config declares libdeflate::libdeflate_static unconditionally,
# but the static split moves libdeflate.a into libdeflate-static, so
# find_package(libdeflate) aborts on an imported target whose file is missing. We
# link the shared library; the archive only has to exist while CMake validates.
TERMUX_PKG_BUILD_DEPENDS="libdeflate-static"
TERMUX_PKG_CONFLICTS="openexr2"
TERMUX_PKG_REPLACES="openexr2"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
-DBUILD_TESTING=OFF
"

termux_step_pre_configure() {
	# Do not forget to bump revision of reverse dependencies and rebuild them
	# after SOVERSION is changed.
	local _SOVERSION=33
	local v=$(sed -En 's/^set\(OPENEXR_LIB_SOVERSION\s+([0-9]+).*/\1/p' CMakeLists.txt)
	if [ "${v}" != "${_SOVERSION}" ]; then
		termux_error_exit "SOVERSION guard check failed."
	fi

	# for code in openjph, which is downloaded by CMakeLists.txt of openexr at build-time
	if [[ "$TERMUX_PKG_API_LEVEL" -lt 28 ]]; then
		CPPFLAGS+=" -Daligned_alloc=memalign"
	fi
}

termux_step_post_make_install() {
	shopt -s nullglob

	local _openjph_stage_dir="$TERMUX_PKG_TMPDIR/openjph-runtime-restage"
	mkdir -p "$_openjph_stage_dir"

	local -a _openjph_sources=(
		"$TERMUX_PKG_BUILDDIR"/_deps/openjph-build/src/core/libopenjph.so*
		"$TERMUX_PREFIX"/lib/libopenjph.so*
		"$TERMUX_PREFIX"/lib64/libopenjph.so*
	)

	local _openjph_source
	for _openjph_source in "${_openjph_sources[@]}"; do
		cp -a "${_openjph_source}" "$_openjph_stage_dir/"
	done

	local -a _openjph_libs=("$_openjph_stage_dir"/libopenjph.so*)
	[[ ${#_openjph_libs[@]} -gt 0 ]] || termux_error_exit "libopenjph runtime payload not found after install."

	local _openjph_lib
	for _openjph_lib in "${_openjph_libs[@]}"; do
		install -Dm600 "${_openjph_lib}" "$TERMUX_PREFIX/lib/$(basename "$_openjph_lib")"
	done

	shopt -u nullglob
}

termux_step_post_massage() {
	shopt -s nullglob
	local f
	for f in lib/libImath*; do
		termux_error_exit "File ${f} should not be contained in this package."
	done
	shopt -u nullglob
}
