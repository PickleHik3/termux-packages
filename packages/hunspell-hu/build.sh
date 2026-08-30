TERMUX_PKG_HOMEPAGE=https://magyarispell.sourceforge.net/
TERMUX_PKG_DESCRIPTION="Hungarian dictionary for hunspell"
TERMUX_PKG_LICENSE="MPL-2.0, LGPL-3.0"
TERMUX_PKG_MAINTAINER="@termux"
# VAJ: the old freedesktop cgit host is decommissioned and 404s every file this
# recipe fetched, so the package could not build at all. Repointed at
# LibreOffice's dictionaries repo -- the same content's canonical home --
# pinned to commit 32b006a2c22a rather than a branch so the URLs
# cannot drift again. Upstream termux still carries the dead URLs.
#
# The dictionaries are newer than the old snapshot, so version and checksums
# move together, exactly as the recipe comment below anticipates.
TERMUX_PKG_VERSION=20260830
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_PLATFORM_INDEPENDENT=true

termux_step_post_get_source() {
	termux_download https://raw.githubusercontent.com/LibreOffice/dictionaries/32b006a2c22a4ac7e8ed3f03346f7b3d85a970a4/hu_HU/README_hu_HU.txt \
			$TERMUX_PKG_SRCDIR/README_hu_HU.txt \
			52b17fc3d53b6935eab747a71894507d702f7f0fde379c819c16cc803005fc84
}

termux_step_make_install() {
	mkdir -p $TERMUX_PREFIX/share/hunspell/
	# On checksum mismatch the files may have been updated:
	#  https://raw.githubusercontent.com/LibreOffice/dictionaries/32b006a2c22a4ac7e8ed3f03346f7b3d85a970a4/hu_HU/hu_HU.aff
	#  https://raw.githubusercontent.com/LibreOffice/dictionaries/32b006a2c22a4ac7e8ed3f03346f7b3d85a970a4/hu_HU/hu_HU.dic
	# In which case we need to bump version and checksum used.
	termux_download https://raw.githubusercontent.com/LibreOffice/dictionaries/32b006a2c22a4ac7e8ed3f03346f7b3d85a970a4/hu_HU/hu_HU.aff \
			$TERMUX_PREFIX/share/hunspell/hu_HU.aff \
			f3a2748dd535cfde2142ab17d0f7f8e4787b03fb25a60829c69ac8d493db4802
	termux_download https://raw.githubusercontent.com/LibreOffice/dictionaries/32b006a2c22a4ac7e8ed3f03346f7b3d85a970a4/hu_HU/hu_HU.dic \
			$TERMUX_PREFIX/share/hunspell/hu_HU.dic \
			97293d670ad4a3b8e7eebef7e25c6e8e939b914c64b6b4672b2bf416b768f990
	touch $TERMUX_PREFIX/share/hunspell/hu_HU.{aff,dic}

	install -Dm600 -t $TERMUX_PREFIX/share/doc/$TERMUX_PKG_NAME \
		$TERMUX_PKG_SRCDIR/README_hu_HU.txt
}
