TERMUX_PKG_HOMEPAGE=https://github.com/fastfetch-cli/fastfetch
TERMUX_PKG_DESCRIPTION="A maintained, feature-rich and performance oriented, neofetch like system information tool (VAJ: animated Kitty graphics)"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="2.67.0"
TERMUX_PKG_REVISION=2
# Pinned to the commit the termux-launcher kitty-animation patch targets
# (recipes/termux/fastfetch in PickleHik3/termux-launcher).
_COMMIT=9c7cfb864ff9154ffe951fae191c14d60bb91544
TERMUX_PKG_SRCURL=https://github.com/fastfetch-cli/fastfetch/archive/${_COMMIT}.tar.gz
TERMUX_PKG_SHA256=d63d9cbf5e012f19eef7b1f7835ac5ef6ddcb034c9a564b32e9ab5228fbf3751
TERMUX_PKG_BUILD_DEPENDS="chafa, dbus, freetype, glib, imagemagick, libandroid-wordexp-static, libelf, libxcb, libxrandr, mesa-dev, ocl-icd, opencl-headers, pulseaudio, vulkan-headers, vulkan-loader-generic, zlib"
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
-DTARGET_DIR_HOME=${TERMUX_ANDROID_HOME}
-DTARGET_DIR_ROOT=${TERMUX_PREFIX}
-DTARGET_DIR_USR=${TERMUX_PREFIX}
-DENABLE_IMAGEMAGICK7=ON
-DENABLE_CHAFA=ON
-DENABLE_ZLIB=ON
"
