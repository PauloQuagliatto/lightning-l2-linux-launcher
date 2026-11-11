#!/bin/bash
# First-run setup for the AppImage (Proton + umu) path.
# Called by launch.sh; safe to re-run - every step is idempotent.
set -e
set -o pipefail

HERE="$(dirname "$(readlink -f "$0")")"
for _lib in config ui preflight umu proton prefix client; do
	# shellcheck source=/dev/null
	. "$HERE/lib/$_lib.sh"
done
unset _lib

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"

# Any failing step (or a cancelled progress dialog, via pipefail) lands
# here. The marker is never written, so the next launch retries setup.
trap 'ui_error "Setup failed or was cancelled. Please try again - if this keeps happening, ask for help in the Lightning-L2 Discord."' ERR

preflight || exit 1

# Client selection happens before the progress dialog: it has prompts and
# progress of its own, and stacking those inside another progress dialog
# is unreadable.
CLIENT_DIR=$(client_resolve) || exit 1
export CLIENT_DIR
log "Client folder: $CLIENT_DIR"

# Everything inside the pipeline writes its own logging to stderr; only
# progress() reaches stdout, which is what ui_progress parses.
(
	progress 5 "Applying the Lightning-L2 system patch..."
	client_patch_sync >&2

	progress 20 "Installing umu-launcher..."
	umu_install >&2

	progress 35 "Downloading GE-Proton (one-time, ~450MB)..."
	proton_install >&2

	progress 65 "Creating the Proton prefix (downloads the Steam runtime once)..."
	prefix_create >&2

	progress 80 "Installing the Tahoma font (fixes missing UI text)..."
	prefix_winetricks tahoma >&2

	progress 90 "Registering MSXML (fixes a crash on destroying items)..."
	prefix_winetricks msxml4 msxml6 >&2

	progress 95 "Verifying the prefix..."
	prefix_verify >&2

	progress 100 "Done!"
) | ui_progress "Setting up Lightning-L2..."

touch "$MARKER"
log "Setup complete."
