#!/bin/bash
# Pinned versions, URLs and every path used by the AppImage (Proton) path.
#
# Everything here is deliberately distinct from the .deb's Wine-GE install
# (~/.local/share/lightning-l2/{wine-ge,prefix,instances}) so both can sit
# on the same machine without either one touching the other's state.

# --- Pinned tool versions ---
# Pinned on purpose rather than PROTONPATH=GE-Proton: players get a
# reproducible environment, and we never write into Steam's
# compatibilitytools.d. Bumping = change the version + the checksum.
#
# NOT the latest GE-Proton, and this is load-bearing. l2.exe is wrapped in
# WinLicense (Oreans) anti-tamper, and anything built on Wine 10 or newer
# cannot run it: L2.bin loads, GameGuard runs its anti-VM probes, the
# WinLicense banner prints, and then L2.bin takes an access violation in
# its own unpacked code and exits before a window opens. Measured here on
# 2026-11-10 against the same client and the same launch command:
#
#   GE-Proton11-12 (wine-staging 11.0)  dies after ~4s
#   GE-Proton10-34 (wine 10)            dies after ~4s
#   GE-Proton9-27  (wine 9)             runs
#   GE-Proton8-32  (wine 8.26)          runs
#   Wine-GE 8-26 (what the .deb pins)   runs  <- control
#
# So: newest build that actually starts the game. Re-test this list
# before bumping, and keep a working version pinned over a maintained one.
GE_PROTON_VERSION="GE-Proton9-27"
GE_PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${GE_PROTON_VERSION}/${GE_PROTON_VERSION}.tar.gz"
GE_PROTON_SHA512="86a2b2962a2509104201b3532bc829d058d666bc8220417f71bd4af660b6d05781e9f684b3982339d695a5fd4babe19e97ec42a82a78311faf99fc1257280623"

UMU_VERSION="1.4.4"
UMU_URL="https://github.com/Open-Wine-Components/umu-launcher/releases/download/${UMU_VERSION}/umu-launcher-${UMU_VERSION}-zipapp.tar"
UMU_SHA256="eb590691841f7fad3fc3ad8fd5db4ccb87849fe7948e62b28ece7a4ee48cc851"

# --- Site endpoints (same ones the .deb uses) ---
SYSTEM_PATCH_URL="https://lightning-l2.com/lightning-l2-system.zip"
SYSTEM_PATCH_VERSION_URL="https://lightning-l2.com/lightning-l2-system-version.txt"
# The genuine, unmodified base client - same file connect.html links to.
CLIENT_URL="https://www.lineage2.org.uk/?wpdmdl=126"

# --- Paths ---
INSTALL_DIR="$HOME/.local/share/lightning-l2"
CONFIG_DIR="$HOME/.config/lightning-l2"
CONFIG_FILE="$CONFIG_DIR/proton.config"
# Read-only reuse: if the .deb already recorded a client folder, seed from
# it instead of making the player re-download 5.6GB. Never written to.
LEGACY_CONFIG_FILE="$CONFIG_DIR/config"

PROTON_ROOT="$INSTALL_DIR/proton"
PROTON_DIR="$PROTON_ROOT/$GE_PROTON_VERSION"
UMU_DIR="$INSTALL_DIR/umu"
UMU_RUN="$UMU_DIR/umu-run"
# umu/Proton treat this as STEAM_COMPAT_DATA_PATH; the real Wine prefix
# ends up at $PREFIX_DIR/pfx.
PREFIX_DIR="$INSTALL_DIR/proton-prefix"
# Which pinned Proton built the prefix. Proton upgrades a prefix happily
# but refuses to downgrade one, so this is what tells us to start over.
PREFIX_STAMP="$PREFIX_DIR/.proton_version"
SLOTS_DIR="$INSTALL_DIR/proton-slots"
INSTANCES_DIR="$INSTALL_DIR/proton-instances"
LOG_DIR="$INSTALL_DIR/logs"

MARKER="$INSTALL_DIR/.proton_setup_complete"
SYSTEM_PATCH_VERSION_FILE="$INSTALL_DIR/.proton_system_patch_version"

GAMEID="lightning-l2"
MAX_SLOTS=6

# Minimum free space under $INSTALL_DIR: Proton (~1.5GB extracted), the
# sniper runtime umu fetches (~800MB) and the prefix itself.
REQUIRED_FREE_KB=$((6 * 1024 * 1024))

log() { echo "[Lightning-L2] $*"; }

# Emits zenity-style progress on stdout (consumed by ui_progress) while
# mirroring the human-readable line to stderr so it lands in the log file
# even when a GUI dialog is swallowing stdout.
progress() {
	echo "$1"
	echo "# $2"
	echo "[Lightning-L2] $2" >&2
}

# download_verified URL DEST sha256sum|sha512sum EXPECTED
# A pinned version is only reproducible if the bytes are checked, and a
# truncated download is otherwise indistinguishable from a good one.
download_verified() {
	local url="$1" dest="$2" prog="$3" expected="$4" actual
	curl -fSL --retry 3 -o "$dest" "$url"
	actual=$("$prog" "$dest" | cut -d' ' -f1)
	if [ "$actual" != "$expected" ]; then
		rm -f "$dest"
		log "Checksum mismatch for $url"
		log "  expected: $expected"
		log "  got:      $actual"
		return 1
	fi
}

config_get() {
	[ -f "$CONFIG_FILE" ] || return 0
	sed -n "s/^$1=//p" "$CONFIG_FILE" | head -n1
}

config_set() {
	mkdir -p "$CONFIG_DIR"
	touch "$CONFIG_FILE"
	local tmp="$CONFIG_FILE.tmp"
	grep -v "^$1=" "$CONFIG_FILE" > "$tmp" 2>/dev/null || true
	echo "$1=$2" >> "$tmp"
	mv "$tmp" "$CONFIG_FILE"
}
