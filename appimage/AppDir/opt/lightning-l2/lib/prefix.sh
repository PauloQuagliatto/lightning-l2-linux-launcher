#!/bin/bash
# Prefix creation and the winetricks verbs the client needs.
#
# umu points both WINEPREFIX and STEAM_COMPAT_DATA_PATH at the same
# directory and Proton then builds the real prefix at <dir>/pfx, so
# $PREFIX_DIR is a container directory, not a Wine prefix itself. The
# .deb's ~/.local/share/lightning-l2/prefix is not reusable here.

# umu_cmd PREFIX VERB [args...]
umu_cmd() {
	local prefix="$1" verb="$2"
	shift 2
	local -a vars=(
		"WINEPREFIX=$prefix"
		"PROTONPATH=$PROTON_DIR"
		"GAMEID=$GAMEID"
		"PROTON_VERB=$verb"
	)
	# STEAM_COMPAT_LIBRARY_PATHS is not optional once there is a client:
	# pressure-vessel exposes $HOME but not arbitrary mounts, and a client
	# on a second drive is common. Omitted rather than passed empty -
	# Proton errors with "unable to use parent for game drive" on an empty
	# value.
	[ -n "${CLIENT_DIR:-}" ] && vars+=("STEAM_COMPAT_LIBRARY_PATHS=$CLIENT_DIR")
	env "${vars[@]}" "$UMU_RUN" "$@"
}

# True when a prefix exists but was built by a different pinned Proton.
# Proton refuses to downgrade a prefix, and the plan's chosen upgrade path
# is a fresh prefix either way, so a version change means start over.
# Nothing a player cares about lives in here: the client install, its
# Option.ini and our config are all outside the prefix.
prefix_needs_rebuild() {
	[ -d "$PREFIX_DIR/pfx" ] || return 1
	[ "$(cat "$PREFIX_STAMP" 2>/dev/null)" = "$GE_PROTON_VERSION" ] && return 1
	return 0
}

prefix_create() {
	if prefix_needs_rebuild; then
		log "Prefix was built by '$(cat "$PREFIX_STAMP" 2>/dev/null || echo unknown)' - rebuilding it for $GE_PROTON_VERSION."
		# The slot 3+ clones came from this prefix, so they are stale too;
		# they re-clone lazily on their next launch.
		rm -rf "$PREFIX_DIR" "$SLOTS_DIR"
	elif [ -d "$PREFIX_DIR/pfx/drive_c/windows" ]; then
		return 0
	fi

	mkdir -p "$PREFIX_DIR"
	# `umu-run ""` is umu's own documented way to build a prefix without
	# launching anything, and the empty argument is required (umu needs a
	# positional exe, and prints usage without one). Proton's createprefix
	# verb is deliberately not used: it is not in umu's PROTON_VERBS, so
	# umu silently replaces it with waitforexitandrun anyway.
	#
	# It always exits non-zero - Wine reports "ShellExecuteEx failed: File
	# not found" for the empty exe after the prefix is already built - so
	# the directory, not the exit status, is what says whether it worked.
	umu_cmd "$PREFIX_DIR" waitforexitandrun "" || true
	if [ ! -d "$PREFIX_DIR/pfx/drive_c/windows" ]; then
		log "Proton did not create a prefix at $PREFIX_DIR/pfx"
		return 1
	fi
	echo -n "$GE_PROTON_VERSION" > "$PREFIX_STAMP"
}

# Proton's font build generates Arial, Times New Roman, Georgia, Courier
# New, Microsoft Sans Serif and the CJK faces - but no Tahoma, so the
# client's UI text is still missing without this. msxml4/msxml6 fix the
# crash on destroying an item. winetricks itself comes from GE-Proton;
# umu runs the bundled copy when the first argument is "winetricks", so
# the host no longer needs winetricks or cabextract installed.
#
# umu's winetricks path exits 1 even when the verbs applied cleanly -
# confirmed live for both tahoma and msxml4/msxml6, including re-runs on
# an already-patched prefix - so the exit status is not a success signal
# here and prefix_verify below is what actually checks the outcome.
prefix_winetricks() {
	umu_cmd "$PREFIX_DIR" waitforexitandrun winetricks -q "$@" || true
}

# Lineage II reads joystick axes as camera input. Any HID device that
# DirectInput enumerates as a joystick while sitting at an off-centre
# axis therefore makes the camera turn by itself, forever, with no way to
# stop it in game. Confirmed here: a QMK/Vial keyboard (Lily58) whose
# "System Control" interface enumerates with usage 0001:0004, which
# dinput happily opened as a joystick for the client.
#
# The client has no real use for a joystick, so every input device the
# kernel knows about gets listed under Wine's own joystick key as
# disabled. That key only affects DirectInput joystick enumeration, so
# listing keyboards, mice and audio HID alongside it costs nothing and
# avoids having to guess which device is the guilty one. Re-applied
# whenever the device list changes, which is what picks up a newly
# plugged device.
#
# Not fixable from the client side: Option.ini/L2.ini hold its
# UseJoystick setting and both are encrypted (Lineage2Ver413).
_prefix_joystick_reg() {
	echo 'Windows Registry Editor Version 5.00'
	echo
	echo '[HKEY_CURRENT_USER\Software\Wine\DirectInput\Joysticks]'
	# Wine names a joystick after the kernel's input device name, not the
	# HID_NAME, so this is the list that has to match.
	sed -n 's/^N: Name="\(.*\)"$/\1/p' /proc/bus/input/devices 2>/dev/null |
		sort -u | sed 's/\\/\\\\/g; s/"/\\"/g; s/.*/"&"="disabled"/'
}

# Per-prefix setup that is not part of creating it: applied to whichever
# prefix this launch actually uses, so the slot 3+ clones get it too.
# Bump TUNE_VERSION to re-apply the registry values to every prefix.
prefix_tune() {
	local pfx="$1" stamp="$1/.tuned" reg="$1/.joysticks.reg"
	local TUNE_VERSION=2

	if [ "$(cat "$stamp" 2>/dev/null)" != "$TUNE_VERSION" ]; then
		log "Tuning the prefix for this client (one-time)..."
		# Grab the pointer for the fullscreen window, so the cursor stays
		# in the game instead of sliding onto the second monitor.
		umu_cmd "$pfx" waitforexitandrun reg add \
			'HKCU\Software\Wine\X11 Driver' /v GrabFullscreen /t REG_SZ /d Y /f || return 1
		# MouseWarpOverride=force was tried for the spinning camera and is
		# wrong: it pins the cursor wherever the client warps it, which is
		# screen centre. Deleted here to repair prefixes that got it.
		umu_cmd "$pfx" waitforexitandrun reg delete \
			'HKCU\Software\Wine\DirectInput' /v MouseWarpOverride /f >/dev/null 2>&1 || true
		echo -n "$TUNE_VERSION" > "$stamp"
	fi

	_prefix_joystick_reg > "$reg.new"
	if cmp -s "$reg.new" "$reg"; then
		rm -f "$reg.new"
		return 0
	fi
	log "Disabling DirectInput joysticks in the prefix (this is what stops the camera spinning)..."
	cp "$reg.new" "$pfx/pfx/drive_c/joysticks.reg"
	if umu_cmd "$pfx" waitforexitandrun regedit /S 'C:\joysticks.reg'; then
		mv "$reg.new" "$reg"
	else
		rm -f "$reg.new"
		log "Could not import it - will retry on the next launch."
	fi
}

# The files the client actually needs, which is the only reliable way to
# tell whether the winetricks verbs above did anything. msxml4 is the
# load-bearing one: Wine has no builtin for it, so it can only be there
# if winetricks really ran.
prefix_verify() {
	local f missing=()
	for f in drive_c/windows/Fonts/tahoma.ttf \
		drive_c/windows/syswow64/msxml4.dll \
		drive_c/windows/syswow64/msxml6.dll; do
		[ -f "$PREFIX_DIR/pfx/$f" ] || missing+=("$f")
	done
	if [ "${#missing[@]}" -gt 0 ]; then
		log "Prefix setup incomplete - missing: ${missing[*]}"
		return 1
	fi
	log "Prefix verified: Tahoma and MSXML are in place."
}
