#!/bin/bash
# Lightning-L2 AppImage entry point: GE-Proton through umu, Wayland-first.
set -e

HERE="$(dirname "$(readlink -f "$0")")"
for _lib in config ui preflight umu proton prefix client slots desktop; do
	# shellcheck source=/dev/null
	. "$HERE/lib/$_lib.sh"
done
unset _lib

# Always log to a file - a Terminal=true window can close before anyone
# reads it, but the log survives. This file, not the terminal, is what to
# check or share for support.
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/proton_launch_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
log "Log: $LOG_FILE"
ls -1t "$LOG_DIR"/proton_launch_*.log 2>/dev/null | tail -n +11 | xargs -r rm -f

# If this fails before the game starts, keep the terminal open long
# enough to actually read the error instead of it flashing shut.
trap 'echo; log "Startup failed - see $LOG_FILE"; read -r -p "Press Enter to close..." _' ERR

desktop_register

# Guard against double-clicks racing a second process against the same
# prefix during the risky early-init window. Released once this instance
# is up, so multiboxing afterwards still works.
exec 200>"$INSTALL_DIR/.proton_launch.lock"
if ! flock -n 200; then
	log "Already starting - ignoring extra launch."
	exit 0
fi

# A new AppImage can pin a different Proton than the one that built the
# prefix. Dropping the marker is what makes setup run again, so the
# prefix gets rebuilt and the winetricks verbs re-applied to it.
if [ -f "$MARKER" ] && prefix_needs_rebuild; then
	log "Pinned Proton is now $GE_PROTON_VERSION - re-running setup."
	rm -f "$MARKER"
fi

# First run, or a previous run was interrupted before finishing.
if [ ! -f "$MARKER" ]; then
	"$HERE/setup.sh"
fi

CLIENT_DIR=$(config_get CLIENT_DIR)
if [ -z "$CLIENT_DIR" ] || [ ! -d "$CLIENT_DIR" ]; then
	ui_error "The recorded Lineage II client folder is missing: ${CLIENT_DIR:-(none)}

If you moved it, delete $CONFIG_FILE and launch again to pick it anew."
	exit 1
fi
export CLIENT_DIR

client_patch_sync
client_strip_anticheat

slot_adopt
if ! slot_acquire; then
	ui_error "$MAX_SLOTS Lightning-L2 clients are already running. Close one before starting another."
	exit 1
fi
PREFIX=$(slot_prefix "$SLOT")
VERB=$(slot_verb "$SLOT")
log "Instance slot: $SLOT, prefix: $PREFIX, PROTON_VERB: $VERB"

# Tune whichever prefix this launch resolved to, after slot_prefix has had
# the chance to clone it: a slot 3+ clone is a prefix in its own right and
# needs its own tuning. Keyed on per-prefix stamps, so it is a no-op once
# applied and re-runs by itself when the input device list changes - which
# is what picks up a newly plugged device. Non-fatal: the stamp is only
# written on success, so a failure retries on the next launch rather than
# blocking the game.
prefix_tune "$PREFIX" || log "Could not tune the prefix - will retry on the next launch."

# --- Launch ---
# No WINEDLLOVERRIDES=d3d9=n, no DXVK copy, no StrictDrawOrdering, and no
# __NV_PRIME_RENDER_OFFLOAD/__GLX_VENDOR_LIBRARY_NAME unset: Proton ships
# DXVK and d3d9 -> Vulkan is its default (PROTON_USE_WINED3D is the
# opt-out), so none of the X11-era workarounds apply here.
export WINEPREFIX="$PREFIX"
export PROTONPATH="$PROTON_DIR"
export GAMEID
export PROTON_VERB="$VERB"
# Not optional: pressure-vessel exposes $HOME but not arbitrary mounts,
# and a client on a second drive is common.
export STEAM_COMPAT_LIBRARY_PATHS="$CLIENT_DIR"
# Our own marker, used by slot_adopt to recognise this process later.
export LIGHTNING_L2_SLOT="$SLOT"

# -fullscreen is a stock Unreal Engine 2 switch and the only way to force
# it here: the client keeps its own setting in Option.ini, which is
# encrypted (Lineage2Ver413) and not ours to edit. Verified against this
# client - the window reports a client-requested fullscreen state with
# the switch and none without it.
CMD=("$UMU_RUN" l2.exe -fullscreen)

# Default is plain XWayland: zero config, every compositor. gamescope is
# opt-in and the real win for this game - fullscreen without changing the
# desktop resolution, proper cursor grab, HiDPI scaling and a genuine
# per-instance window, which matters for 6-boxing.
if [ "${USE_GAMESCOPE:-0}" = "1" ]; then
	if command -v gamescope >/dev/null 2>&1; then
		# shellcheck disable=SC2206 # intentional word-splitting of user args
		CMD=(gamescope ${GAMESCOPE_ARGS:--f} -- "${CMD[@]}")
	else
		log "USE_GAMESCOPE=1 but gamescope is not installed - falling back to XWayland."
	fi
fi
# PROTON_ENABLE_WAYLAND=1 works if the player exports it, but it is
# documented experimental (GE calls it YMMV, and Proton 11 removed
# Proton 10's automated Wayland hacks pending a real implementation). For
# a 2012 fixed-function D3D9 client it is the riskiest path, so it is
# never set here.

cd "$CLIENT_DIR/system"
log "Running: ${CMD[*]}"
"${CMD[@]}" &
GAME_PID=$!

# Hold the lock through the risky early-init window only, then release
# it, so launching a second account afterwards proceeds normally.
sleep 8
flock -u 200

wait "$GAME_PID"
