#!/bin/bash
# Multi-instance slots: locking, prefix choice and PROTON_VERB.
#
# Slots 1-2 share the main prefix (years of successful dual-boxing on the
# .deb). A 3rd instance on that same prefix reliably crashes: the client
# is wrapped in WinLicense (Oreans) anti-tamper, and the path it takes on
# noticing a 3rd sibling in Wine's named-object namespace computes a bad
# jump target and segfaults before a window opens - traced live with
# WINEDEBUG=+seh,+exception. The container does not change Wine's
# named-object namespace, so this is unchanged under Proton; slot 3+ gets
# its own isolated prefix, which sidesteps the trigger entirely.

# Adopt a client that is running without its launcher holding the slot
# lock (an instance started by an older build, still open across an
# update). Without this, a new launch sees the slot as free and lands as
# an untracked 3rd process on the shared prefix - exactly the crash
# above, reached through the update gap.
#
# Matched on our own injected LIGHTNING_L2_SLOT, not on WINEPREFIX: Proton
# rewrites WINEPREFIX to <dir>/pfx inside the container, so a WINEPREFIX
# match would silently never fire. l2.exe as well as l2.bin because the
# process name depends on which Wine loader path the client takes.
slot_adopt() {
	local pid n
	mkdir -p "$INSTANCES_DIR"
	for pid in $(pgrep -x 'l2.bin|l2.exe' 2>/dev/null); do
		[ -r "/proc/$pid/environ" ] || continue
		n=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null |
			sed -n 's/^LIGHTNING_L2_SLOT=//p' | head -n1)
		[ -n "$n" ] || continue
		case "$n" in ''|*[!0-9]*) continue ;; esac
		log "Adopting running client (pid $pid) into slot $n"
		# A small background holder keeps that slot claimed for as long as
		# the real process lives, then exits on its own. The adopted
		# process is never touched.
		(
			exec {adopt_fd}>"$INSTANCES_DIR/slot-$n.lock"
			flock -n "$adopt_fd" || exit 0
			while kill -0 "$pid" 2>/dev/null; do sleep 5; done
		) &
		disown
	done
	# Let the holders actually acquire their flock before this launch's
	# own slot loop starts racing them.
	sleep 0.5
}

# Sets SLOT and keeps its lock held in this shell - must not be called in
# a subshell, or the lock dies with it.
slot_acquire() {
	local i
	mkdir -p "$INSTANCES_DIR"
	SLOT=0
	for i in $(seq 1 "$MAX_SLOTS"); do
		exec {SLOT_FD}>"$INSTANCES_DIR/slot-$i.lock"
		if flock -n "$SLOT_FD"; then
			SLOT=$i
			break
		fi
		exec {SLOT_FD}>&-
	done
	[ "$SLOT" -ne 0 ]
}

slot_prefix() {
	local slot="$1" dir
	if [ "$slot" -le 2 ]; then
		echo "$PREFIX_DIR"
		return 0
	fi
	dir="$SLOTS_DIR/box$slot"
	if [ ! -d "$dir" ]; then
		log "First launch in slot $slot - cloning an isolated Proton prefix (one-time, ~700MB)..." >&2
		mkdir -p "$SLOTS_DIR"
		# Copies the whole container directory including pfx, so the clone
		# already has Tahoma/msxml applied.
		cp -a "$PREFIX_DIR" "$dir"
	fi
	echo "$dir"
}

# The default waitforexitandrun waits for an existing wineserver in the
# prefix to exit, which would hang a second instance. But a static
# "slot 1 -> waitforexitandrun, slot 2 -> runinprefix" mapping is also
# wrong: if slot 1 closes while slot 2 plays on, a fresh slot-1 launch
# would wait on slot 2's wineserver.
#
# Correct rule, per prefix: whoever is first in gets waitforexitandrun,
# anyone joining a live prefix gets runinprefix. Probed with a
# non-blocking flock of the sibling slot locks rather than inventing a
# second mechanism. (The probe takes and immediately drops the sibling
# lock; a concurrent launch could lose that race and land one slot
# further along, which is harmless - both slots share this prefix.)
#
# umu's FAQ also warns that the rest of the Proton config must match
# between instances sharing a prefix. It does: same pinned Proton, same
# env, set in one place.
slot_verb() {
	local slot="$1" i fd
	# Slot 3+ owns its prefix outright, so it is always first in.
	if [ "$slot" -gt 2 ]; then
		echo waitforexitandrun
		return 0
	fi
	for i in 1 2; do
		[ "$i" = "$slot" ] && continue
		exec {fd}>"$INSTANCES_DIR/slot-$i.lock"
		if ! flock -n "$fd"; then
			exec {fd}>&-
			echo runinprefix
			return 0
		fi
		exec {fd}>&-
	done
	echo waitforexitandrun
}
