#!/bin/bash
# Fetches the pinned GE-Proton build into our own tools directory.
# Never ~/.local/share/Steam/compatibilitytools.d - we don't own that.

proton_install() {
	[ -x "$PROTON_DIR/proton" ] && return 0

	local tmp
	mkdir -p "$PROTON_DIR"
	tmp=$(mktemp -d "$INSTALL_DIR/.proton-dl.XXXXXX")
	download_verified "$GE_PROTON_URL" "$tmp/proton.tar.gz" sha512sum "$GE_PROTON_SHA512"
	# --strip-components=1 because the tarball's top-level directory is
	# "$GE_PROTON_VERSION-x86_64", not "$GE_PROTON_VERSION" - extracting
	# into the version-named directory ourselves keeps the layout the same
	# whatever upstream names that folder, and keeps two pinned versions
	# from colliding on an upgrade.
	tar xf "$tmp/proton.tar.gz" -C "$PROTON_DIR" --strip-components=1
	rm -rf "$tmp"

	if [ ! -x "$PROTON_DIR/proton" ]; then
		log "Extracted $GE_PROTON_VERSION but $PROTON_DIR/proton is missing."
		return 1
	fi
	log "$GE_PROTON_VERSION installed at $PROTON_DIR"
}
