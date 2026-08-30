TERMUX_PKG_HOMEPAGE=https://www.opentaal.org/
TERMUX_PKG_DESCRIPTION="Dutch dictionary for hunspell"
TERMUX_PKG_LICENSE="custom"
TERMUX_PKG_LICENSE_FILE="LICENSE.txt"
TERMUX_PKG_MAINTAINER="@termux"
# VAJ: the old freedesktop cgit host is decommissioned and 404s every file this
# recipe fetched, so the package could not build at all. Repointed at
# LibreOffice's dictionaries repo -- the same content's canonical home --
# pinned to commit 32b006a2c22a rather than a branch so the URLs cannot drift
# again. Upstream termux still carries the dead URLs.
#
# nl_NL was also reorganised upstream: README_NL.txt is now README.md, and the
# two separate licence files (license_en_EN.txt and licentie_nl_NL.txt) were
# merged into one LICENSE.txt, so the licence metadata and install step follow.
#
# The dictionaries are newer than the old snapshot, so version and checksums
# move together, as the comment in termux_step_make_install anticipates.
TERMUX_PKG_VERSION=20260830
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_PLATFORM_INDEPENDENT=true

_DICT_BASE=https://raw.githubusercontent.com/LibreOffice/dictionaries/32b006a2c22a4ac7e8ed3f03346f7b3d85a970a4

termux_step_post_get_source() {
	termux_download $_DICT_BASE/nl_NL/README.md \
			$TERMUX_PKG_SRCDIR/README.md \
			aa4685a78f32d0d24a67dd5043ef4e39acc8720c3e416fe5d201985980dbc004
	termux_download $_DICT_BASE/nl_NL/LICENSE.txt \
			$TERMUX_PKG_SRCDIR/LICENSE.txt \
			2189c248cbc054445aeac6cd65b87eebd0a115efeb55ed498b0f2a73441805dd
}

termux_step_make_install() {
	mkdir -p $TERMUX_PREFIX/share/hunspell/
	# On checksum mismatch the files may have been updated:
	#  $_DICT_BASE/nl_NL/nl_NL.aff
	#  $_DICT_BASE/nl_NL/nl_NL.dic
	# In which case we need to bump version and checksum used.
	termux_download $_DICT_BASE/nl_NL/nl_NL.aff \
			$TERMUX_PREFIX/share/hunspell/nl_NL.aff \
			f0233d4f721f4661cf5f4d05ed2739549322bf3b6b66764b55a38257e1e16e6f
	termux_download $_DICT_BASE/nl_NL/nl_NL.dic \
			$TERMUX_PREFIX/share/hunspell/nl_NL.dic \
			bc28af45307700a9927ad5719184da44dfd7eed4f707b8c1477f6d8a21b586a6
	touch $TERMUX_PREFIX/share/hunspell/nl_NL.{aff,dic}

	install -Dm600 -t $TERMUX_PREFIX/share/doc/$TERMUX_PKG_NAME \
		$TERMUX_PKG_SRCDIR/README.md
}
