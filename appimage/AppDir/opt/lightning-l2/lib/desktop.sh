#!/bin/bash
# Desktop self-registration.
#
# An AppImage is not registered with the desktop by default, and
# hyprlauncher - like every other XDG launcher - only scans
# ~/.local/share/applications. Without this the app is invisible no
# matter where the file sits. Done on every launch so moving or renaming
# the AppImage doesn't leave a dead menu entry. Deliberately does not
# depend on AppImageLauncher or appimaged.

desktop_register() {
	# $APPIMAGE is the AppImage's own absolute path, set by the runtime.
	# $APPDIR is the mount point and changes every run, so it is wrong for
	# Exec=. Running the AppDir directly (extracted, or from a checkout)
	# gives no stable path to record, so skip rather than write a broken
	# entry.
	if [ -z "${APPIMAGE:-}" ]; then
		log "Not running as an AppImage - skipping desktop registration."
		return 0
	fi

	local apps="$HOME/.local/share/applications"
	local entry="$apps/lightning-l2.desktop"
	local icons="$HOME/.local/share/icons/hicolor"
	local changed=0 src size dest

	mkdir -p "$apps"
	if ! grep -qxF "Exec=\"$APPIMAGE\"" "$entry" 2>/dev/null; then
		log "Registering desktop entry -> $APPIMAGE"
		cat > "$entry" <<EOF
[Desktop Entry]
Name=Lightning-L2
Comment=Play Lineage II on the Lightning-L2 server
Exec="$APPIMAGE"
Icon=lightning-l2
Terminal=true
Type=Application
Categories=Game;
StartupNotify=true
EOF
		chmod +x "$entry"
		changed=1
	fi

	for src in "$APPDIR"/usr/share/icons/hicolor/*/apps/lightning-l2.png; do
		[ -f "$src" ] || continue
		size=$(basename "$(dirname "$(dirname "$src")")")
		dest="$icons/$size/apps/lightning-l2.png"
		if [ ! -f "$dest" ]; then
			mkdir -p "$(dirname "$dest")"
			cp "$src" "$dest"
			changed=1
		fi
	done

	if [ "$changed" -eq 1 ]; then
		update-desktop-database "$apps" >/dev/null 2>&1 || true
		gtk-update-icon-cache "$icons" >/dev/null 2>&1 || true
	fi
	return 0
}
