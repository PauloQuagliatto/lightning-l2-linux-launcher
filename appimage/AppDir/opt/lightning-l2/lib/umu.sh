#!/bin/bash
# umu-launcher bootstrap.
#
# GE-Proton is built against the Steam Linux Runtime container and is only
# supported outside Steam through umu (GloriousEggroll's own README says
# so). umu fetches the sniper container itself and runs Proton inside it
# exactly as Steam would, with no Steam install - the same thing Heroic
# and Lutris do. The zipapp is a single Python file, so "installing" it is
# unpacking one tar.

umu_install() {
	# Checked against a stamp, not just "the file exists": the zipapp
	# carries no queryable version, and an unpinned copy left here by
	# anything else would otherwise be used as-is, which defeats the point
	# of pinning.
	local stamp="$UMU_DIR/.version"
	if [ -x "$UMU_RUN" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$UMU_VERSION" ]; then
		return 0
	fi

	local tmp
	tmp=$(mktemp -d "$INSTALL_DIR/.umu-dl.XXXXXX")
	download_verified "$UMU_URL" "$tmp/umu.tar" sha256sum "$UMU_SHA256"
	# Archive layout is umu/umu-run + umu/umu_run.py.
	tar xf "$tmp/umu.tar" -C "$tmp"
	mkdir -p "$UMU_DIR"
	cp "$tmp/umu/umu-run" "$UMU_RUN"
	chmod +x "$UMU_RUN"
	echo -n "$UMU_VERSION" > "$stamp"
	rm -rf "$tmp"
	log "umu $UMU_VERSION installed at $UMU_RUN"
}
