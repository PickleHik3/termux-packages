TERMUX_PKG_HOMEPAGE=https://www.gnu.org/software/recutils/
TERMUX_PKG_DESCRIPTION="Set of tools and libraries to access human-editable, plain text databases called recfiles"
TERMUX_PKG_LICENSE="GPL-3.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=1.9
TERMUX_PKG_REVISION=1
TERMUX_PKG_SRCURL=https://mirrors.kernel.org/gnu/recutils/recutils-${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=6301592b0020c14b456757ef5d434d49f6027b8e5f3a499d13362f205c486e0e
# libandroid-spawn is already kept out by AVOID_GNULIB in
# termux_step_configure_autotools.sh, which sets ac_cv_func_posix_spawn=no and
# ac_cv_func_posix_spawnp=no for every autotools package. This recipe additionally
# claimed the header itself was absent, and that is what broke the build: gnulib
# substitutes @HAVE_SPAWN_H@ into its own spawn.h, so the generated header ends up
# with "#if 0" around its "#include_next <spawn.h>" and never sees bionic's
# definitions. Its POSIX_SPAWN_USEVFORK fallback is written in terms of
# POSIX_SPAWN_RESETIDS and friends, so all of them come out undeclared and
# lib/execute.c fails on gnulib's own static assertion.
#
# Verified against the NDK sysroot: with the system header included, gnulib's
# #ifndef fallback computes USEVFORK as the next free bit (bionic hides its own
# behind __USE_GNU) and the no-overlap assertion compiles with 0 errors.
TERMUX_PKG_EXTRA_MAKE_ARGS="lispdir=${TERMUX_PREFIX}/share/emacs/site-lisp"
