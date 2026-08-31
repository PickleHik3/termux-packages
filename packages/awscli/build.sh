TERMUX_PKG_HOMEPAGE=https://aws.amazon.com/cli
TERMUX_PKG_DESCRIPTION="Universal Command Line Interface for Amazon Web Services"
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_LICENSE_FILE="LICENSE.txt, exe/assets/THIRD_PARTY_LICENSES"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="2.36.32"
TERMUX_PKG_SRCURL="https://github.com/aws/aws-cli/archive/refs/tags/$TERMUX_PKG_VERSION.tar.gz"
TERMUX_PKG_SHA256=f4b66c1654e7ec4cce75f6604a6962d62b577ef353b44753fe83caf20bf2bd22
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_UPDATE_VERSION_REGEXP="\d+.\d+.\d+"
TERMUX_PKG_DEPENDS="libandroid-posix-semaphore, libandroid-support, mandoc"
TERMUX_PKG_SUGGESTS="groff"
TERMUX_PKG_BUILD_DEPENDS="aosp-libs, python-pip, cmake, ldd"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
--with-install-type=portable-exe
--with-download-deps
PYTHON=$TERMUX_PREFIX/bin/python
"

# shellcheck disable=SC2115
termux_step_pre_configure() {
	export LDFLAGS+=" -lm"
	export AWS_CRT_BUILD_FORCE_STATIC_LIBS=1

	if [[ "$TERMUX_ON_DEVICE_BUILD" == "true" ]]; then
		return
	fi

	[[ -n "$TERMUX_PKG_TMPDIR" ]] || termux_error_exit "TERMUX_PKG_TMPDIR is unset"
	rm -rf "${TERMUX_PKG_TMPDIR}/bin"
	mkdir -p "$TERMUX_PKG_TMPDIR/bin"

	local -A tools=(
		[as]=AS
		[cc]=CC
		[cpp]=CPP
		[c++]=CXX
		[ld]=LD
		[ar]=AR
		[objcopy]=OBJCOPY
		[objdump]=OBJDUMP
		[ranlib]=RANLIB
		[readelf]=READELF
		[strip]=STRIP
		[nm]=NM
		[cxxfilt]=CXXFILT
	)

	local target cmd path
	for target in "${!tools[@]}"; do
		# indirection syntax e.g. target=nm, cmd=$NM
		cmd="${!tools[$target]}"
		path="$(command -v "$cmd")" || continue
		ln -sf "$path" "$TERMUX_PKG_TMPDIR/bin/$target"
	done

	local PYTHON_INCLUDE="$TERMUX_PREFIX/include/python$TERMUX_PYTHON_VERSION"

	TERMUX_PROOT_EXTRA_ENV_VARS=" \
	LD_PRELOAD= LD_LIBRARY_PATH= \
	AWS_CRT_BUILD_FORCE_STATIC_LIBS=$AWS_CRT_BUILD_FORCE_STATIC_LIBS \
	PIP_VERBOSE=1 \
	PIP_NO_CACHE_DIR=1 \
	AS=$AS \
	CC=$CC \
	CPP=$CPP \
	CXX=$CXX \
	LD=$LD \
	AR=$AR \
	OBJCOPY=$OBJCOPY \
	OBJDUMP=$OBJDUMP \
	RANLIB=$RANLIB \
	READELF=$READELF \
	STRIP=$STRIP \
	NM=$NM \
	CXXFILT=$CXXFILT \
	CFLAGS='$CFLAGS -I$PYTHON_INCLUDE' \
	CPPFLAGS='$CPPFLAGS -I$PYTHON_INCLUDE' \
	CXXFLAGS='$CXXFLAGS' \
	LDFLAGS='$LDFLAGS' \
	PYTHON='$TERMUX_PREFIX/bin/python3' \
	PYI_LOG_LEVEL=DEBUG \
	PYI_STATIC_ZLIB=1 \
	" termux_setup_proot
	# NOTE: awscli still does not build. PYI_STATIC_ZLIB above does take effect -- waf
	# stops probing for the system libz and compiles pyinstaller's bundled copy
	# instead -- but that then dies on "zconf.h:456: fatal error: 'sys/types.h' file
	# not found". The real defect is that waf's bootloader build gets no usable header
	# search path under proot at all, which is also why its configure reports
	# semaphore.h and sys/sem.h as missing; "Checking for library z : no" was a
	# symptom of the same thing rather than a missing zlib. Fixing this means getting
	# CPPFLAGS/--sysroot through to waf, which needs live iteration inside proot.
	# The flag is kept only because it surfaces the accurate diagnostic.
}

termux_step_configure() {
	if [[ "$TERMUX_ON_DEVICE_BUILD" == "true" ]]; then
		termux_step_configure_autotools
		return
	fi

	termux-proot-run env PATH="$TERMUX_PKG_TMPDIR/bin:$TERMUX_PREFIX/bin:$PATH" \
		"$TERMUX_PKG_SRCDIR/configure" --prefix="$TERMUX_PREFIX" $TERMUX_PKG_EXTRA_CONFIGURE_ARGS
}

termux_step_post_configure() {
	cat <<-EOF >"$TERMUX_PKG_TMPDIR"/post_config.sh
		python3 -m venv $TERMUX_PKG_TMPDIR/venv
		source $TERMUX_PKG_TMPDIR/venv/bin/activate
		pip3 install pip-tools
		python3 $TERMUX_PKG_SRCDIR/scripts/regenerate-lock-files
		deactivate
	EOF

	if [[ "$TERMUX_ON_DEVICE_BUILD" == "true" ]]; then
		bash "$TERMUX_PKG_TMPDIR"/post_config.sh
		return
	fi

	termux-proot-run env PATH="$TERMUX_PKG_TMPDIR/bin:$TERMUX_PREFIX/bin:$PATH" \
		bash "$TERMUX_PKG_TMPDIR"/post_config.sh
}

termux_step_make() {
	if [[ "$TERMUX_ON_DEVICE_BUILD" == "true" ]]; then
		make
		return
	fi

	termux-proot-run \
		-b "$TERMUX_STANDALONE_TOOLCHAIN/sysroot/usr/include/android:$TERMUX__PREFIX__INCLUDE_DIR/android" \
		env PATH="$TERMUX_PKG_TMPDIR/bin:$TERMUX_PREFIX/bin:$PATH" \
		make
}

termux_step_make_install() {
	if [[ "$TERMUX_ON_DEVICE_BUILD" == "true" ]]; then
		make install
		return
	fi

	termux-proot-run env PATH="$TERMUX_PKG_TMPDIR/bin:$TERMUX_PREFIX/bin:$PATH" \
		make install
}
