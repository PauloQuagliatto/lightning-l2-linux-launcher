#!/bin/bash
# Finding (or fetching) the Lineage II client, and keeping the
# Lightning-L2 system patch in sync with the site.

# Where an auto-downloaded client lands - the standard Downloads folder
# when xdg-user-dirs can tell us, ~/Downloads otherwise.
client_download_dir() {
	local base
	base=$(xdg-user-dir DOWNLOAD 2>/dev/null || true)
	[ -n "$base" ] || base="$HOME/Downloads"
	echo "$base/Lineage2"
}

# Case-insensitive: different client packages ship system/l2.exe under
# either casing and a Linux filesystem cares. Finding nothing is normal
# (first run), so every call site guards with `|| true` - set -e would
# otherwise treat it as fatal.
find_client_root() {
	local exe
	[ -d "$1" ] || return 1
	exe=$(find "$1" -maxdepth 4 -ipath "*/system/l2.exe" 2>/dev/null | head -n1) || true
	[ -n "$exe" ] && dirname "$(dirname "$exe")"
}

_client_download() {
	local dl_dir="$1" zip_path="$2" base content_len curl_pid curl_status unzip_pid unzip_status
	base=$(dirname "$dl_dir")

	local avail required=$((14 * 1024 * 1024))  # zip + extracted copy, with margin
	mkdir -p "$base"
	avail=$(df --output=avail -k "$base" 2>/dev/null | tail -n1 | tr -d ' ') || true
	if [ -z "$avail" ] || [ "$avail" -lt "$required" ] 2>/dev/null; then
		ui_error "Not enough free space in $base for the client download (need ~14GB free). Free up space and try again, or point Lightning-L2 at a client you already have."
		return 1
	fi

	mkdir -p "$dl_dir"
	content_len=$(curl -sIL --max-time 20 "$CLIENT_URL" 2>/dev/null |
		tr -d '\r' | awk -F': ' 'tolower($1)=="content-length"{v=$2} END{print v}') || true

	# -C - resumes a partial download from an earlier cancelled attempt
	# instead of restarting the ~5.6GB transfer from zero.
	curl -fSL -C - -o "$zip_path" "$CLIENT_URL" &
	curl_pid=$!
	(
		while kill -0 "$curl_pid" 2>/dev/null; do
			cur=$(stat -c%s "$zip_path" 2>/dev/null || echo 0)
			if [ -n "$content_len" ] && [ "$content_len" -gt 0 ] 2>/dev/null; then
				pct=$(( cur * 100 / content_len ))
				[ "$pct" -gt 99 ] && pct=99
			else
				pct=50
			fi
			progress "$pct" "Downloading Lineage II client: $(( cur / 1024 / 1024 ))MB$( [ -n "$content_len" ] && echo "/$(( content_len / 1024 / 1024 ))MB" )"
			sleep 1
		done
		# Always land on 100 so --auto-close actually closes the dialog;
		# stalling below 100 would leave it open, blocking everything
		# after it on a manual close.
		progress 100 "Download complete."
	) | ui_progress "Starting download..." || true
	curl_status=0
	wait "$curl_pid" || curl_status=$?

	if [ "$curl_status" -ne 0 ]; then
		rm -f "$zip_path"
		ui_error "Downloading the client failed (network error or the mirror is unreachable). Please download it manually from lineage2.org.uk and point Lightning-L2 at that folder instead."
		return 1
	fi
	if ! unzip -tq "$zip_path" >/dev/null 2>&1; then
		rm -f "$zip_path"
		ui_error "The downloaded client file was corrupted. Please try again, or download it manually from lineage2.org.uk."
		return 1
	fi

	unzip -oq "$zip_path" -d "$dl_dir" &
	unzip_pid=$!
	(
		while kill -0 "$unzip_pid" 2>/dev/null; do
			progress 50 "Extracting client files - this takes a few minutes..."
			sleep 1
		done
		progress 100 "Extraction complete."
	) | ui_progress "Extracting client..." || true
	unzip_status=0
	wait "$unzip_pid" || unzip_status=$?
	[ "$unzip_status" -eq 0 ] && rm -f "$zip_path"
	return 0
}

# A folder we found on our own is only ever a suggestion - the player may
# have several clients, or the path the .deb recorded may be stale or on a
# drive that is no longer the one they want to use.
_client_confirm() {
	ui_question "Found a Lineage II client here:

$1

Use this folder?" "Use this folder" "Choose another folder"
}

# Records CLIENT_DIR in the new config and echoes it. Order: the folder
# the player already picked for *this* launcher (silent - they chose it),
# then the .deb's config (read-only reuse so nobody re-downloads 5.6GB),
# then a previous auto-download, then ask / offer to fetch. The two
# guesses in the middle are always confirmed before being used.
client_resolve() {
	local dir="" cand dl_dir found=0
	cand=$(config_get CLIENT_DIR)
	if [ -n "$cand" ] && [ -d "$cand" ]; then
		echo "$cand"
		return 0
	fi

	if [ -f "$LEGACY_CONFIG_FILE" ]; then
		cand=$(sed -n 's/^CLIENT_DIR=//p' "$LEGACY_CONFIG_FILE" | head -n1)
		if [ -n "$cand" ] && [ -d "$cand" ]; then
			found=1
			if _client_confirm "$cand"; then
				log "Using the client folder recorded by the existing install: $cand" >&2
				dir="$cand"
			fi
		fi
	fi

	if [ -z "$dir" ]; then
		dl_dir=$(client_download_dir)
		cand=$(find_client_root "$dl_dir") || true
		if [ -n "$cand" ]; then
			found=1
			_client_confirm "$cand" && dir="$cand"
		fi
	fi

	# Only offer the download when there was nothing to find at all -
	# declining a folder we found means "let me pick one", not "fetch 5.6GB".
	if [ -z "$dir" ] && [ "$found" -eq 0 ] && ui_question \
		"No Lineage II client was found on this computer.

Most players who get stuck here downloaded only the launcher and skipped the base game client - it's a separate ~5.6GB download that Lightning-L2 doesn't bundle.

Download it automatically now?" \
		"Download it for me (~5.6GB)" "I already have it"; then
		if _client_download "$dl_dir" "$dl_dir/lineage2-highfive-client.zip" >&2; then
			dir=$(find_client_root "$dl_dir") || true
			[ -n "$dir" ] || ui_error "The downloaded client didn't extract correctly. Please download it manually from lineage2.org.uk and point Lightning-L2 at that folder instead."
		fi
	fi

	# Nothing found/downloaded, or the player picked "I already have it".
	if [ -z "$dir" ]; then
		dir=$(ui_select_dir "Select your Lineage II High Five client folder") || {
			ui_error "Setup cancelled - no client folder selected."
			return 1
		}
		if [ ! -f "$dir/system/l2.exe" ] && [ ! -f "$dir/LineageII.exe" ]; then
			ui_error "That folder doesn't look like a Lineage II client (no l2.exe/LineageII.exe found). Please point to the folder containing 'system\\l2.exe'."
			return 1
		fi
	fi

	config_set CLIENT_DIR "$dir"
	echo "$dir"
}

# A pre-existing, differently-cased copy (e.g. "ItemName-E.DAT" from
# whatever client the player started from) is not overwritten by unzip on
# a case-sensitive filesystem - it just sits next to the correct file, and
# which one Wine reads is undefined. Keep exactly one, unambiguous copy.
_client_drop_case_dupes() {
	local stale
	for stale in "$CLIENT_DIR"/system/[Ii][Tt][Ee][Mm][Nn][Aa][Mm][Ee]-[Ee].[Dd][Aa][Tt]; do
		[ -e "$stale" ] || continue
		[ "$stale" = "$CLIENT_DIR/system/ItemName-e.dat" ] && continue
		log "Removing stale case-duplicate: $stale"
		rm -f "$stale"
	done
}

# GameGuard's kernel driver cannot load under Wine. Removing just these
# files while keeping GameGuard.des is what lets the client start.
#
# Called on every launch, not only after a patch extraction: the patch
# being already up to date is the common case, and a client folder that
# still has these files (a fresh copy, a restored backup, a folder the
# player just pointed us at) would otherwise never get them stripped.
# Three idempotent rm -f calls, so running it every time costs nothing.
client_strip_anticheat() {
	rm -f "$CLIENT_DIR/system/npkcusb.sys" \
		"$CLIENT_DIR/system/npkcrypt.sys" \
		"$CLIENT_DIR/system/npkcrypt.vxd"
}

# The standing re-sync mechanism: compares a tiny remote version file
# against the one recorded locally and only re-downloads the zip when
# they differ, so every future system-patch fix reaches installed players
# on their next launch without shipping a new AppImage.
#
# Two things here are load-bearing, both from real reports against the
# .deb:
#  - the version marker is written only after unzip reports success. The
#    original wrote it unconditionally, so a failed extraction got
#    recorded as "up to date" and masked itself permanently.
#  - the zip URL is cache-busted with the version string. The bare URL
#    sits behind a CDN cache for hours (confirmed serving a stale build
#    after a real deploy), and only a different URL guarantees a miss.
#    The version endpoint itself is never cached.
#
# Best-effort throughout: a network failure logs and falls through to
# launching normally, and CLIENT_DIR is never touched on an empty remote
# version.
client_patch_sync() {
	local remote local_version url zip unzip_err

	remote=$(curl -fsSL --max-time 10 "$SYSTEM_PATCH_VERSION_URL" 2>/dev/null || true)
	local_version=$(cat "$SYSTEM_PATCH_VERSION_FILE" 2>/dev/null || true)
	log "System patch version: local '${local_version:-none}', remote '${remote:-unreachable}'"

	if [ -n "$remote" ] && [ "$remote" = "$local_version" ]; then
		log "System patch already up to date."
		return 0
	fi
	if [ -z "$remote" ] && [ -n "$local_version" ]; then
		log "Version endpoint unreachable - keeping the patch already applied."
		return 0
	fi

	if [ -n "$remote" ]; then
		url="${SYSTEM_PATCH_URL}?v=${remote}"
	else
		# Nothing applied yet and no version to bust the cache with: the
		# bare URL is still correct on a fresh install, since nothing has
		# ever been cached here with the wrong content.
		url="$SYSTEM_PATCH_URL"
	fi

	zip="$INSTALL_DIR/system-patch.zip"
	log "Applying system patch (${local_version:-none} -> ${remote:-unknown})..."
	if ! curl -fsSL --max-time 300 -o "$zip" "$url" 2>/dev/null; then
		log "Could not fetch the system patch - will retry next launch."
		return 0
	fi

	unzip_err="$INSTALL_DIR/.system_patch_unzip_error.log"
	if ! unzip -o -q "$zip" -d "$CLIENT_DIR" 2>"$unzip_err"; then
		log "System patch extraction failed - version marker NOT updated, will retry next launch. unzip said:"
		sed 's/^/[Lightning-L2]   /' "$unzip_err" 2>/dev/null || true
		return 0
	fi
	rm -f "$unzip_err"

	_client_drop_case_dupes
	client_strip_anticheat

	# Log what is actually on disk now, so a future report can be
	# diagnosed from this log alone.
	if [ -f "$CLIENT_DIR/system/ItemName-e.dat" ]; then
		log "system/ItemName-e.dat now: $(md5sum "$CLIENT_DIR/system/ItemName-e.dat" | cut -d' ' -f1), $(stat -c '%s bytes, modified %y' "$CLIENT_DIR/system/ItemName-e.dat" 2>/dev/null)"
	else
		log "WARNING: system/ItemName-e.dat does not exist after extraction - the zip's internal layout may not match this client's system/ folder."
	fi

	if [ -n "$remote" ]; then
		echo -n "$remote" > "$SYSTEM_PATCH_VERSION_FILE"
		log "System patch updated to $remote."
	else
		log "System patch applied, but its version is unknown - the next launch will re-apply it once."
	fi
}
