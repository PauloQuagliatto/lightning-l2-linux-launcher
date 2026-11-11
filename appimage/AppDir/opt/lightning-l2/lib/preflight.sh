#!/bin/bash
# Host requirement checks. The sniper container supplies the 32-bit
# userspace Wine used to need from the distro, so this list is short -
# but it cannot supply GPU drivers, which is the one genuinely
# distro-specific thing left.

# 1 = 32-bit ELF, 2 = 64-bit. Avoids depending on `file`, which plenty of
# minimal installs don't have.
_elf_class() {
	dd if="$1" bs=1 skip=4 count=1 2>/dev/null | od -An -tu1 | tr -d ' []'
}

# Resolves an ICD's library_path the way the loader does: absolute or
# relative-to-the-json path as given, otherwise by name in the usual
# 32-bit library directories.
_find_icd_lib() {
	local json="$1" lib="$2" d
	case "$lib" in
		/*) echo "$lib"; return ;;
		*/*) echo "$(dirname "$json")/$lib"; return ;;
	esac
	for d in /usr/lib32 /usr/lib/i386-linux-gnu /usr/lib/i686-linux-gnu \
		/usr/lib/i386-linux-gnu/vulkan /usr/lib32/vulkan /usr/lib/i386 /lib32; do
		[ -e "$d/$lib" ] && { echo "$d/$lib"; return; }
	done
	echo ""
}

# Deliberately non-blocking. The reliable test is vulkaninfo, which is
# often not installed, so this reads the ICD manifests instead and asks
# whether any of them resolves to a 32-bit library. A false negative must
# never stop a working setup - so it logs loudly and continues.
check_vulkan32() {
	local json lib path found=0
	for json in /usr/share/vulkan/icd.d/*.json /usr/local/share/vulkan/icd.d/*.json \
		/etc/vulkan/icd.d/*.json "${XDG_DATA_HOME:-$HOME/.local/share}"/vulkan/icd.d/*.json; do
		[ -f "$json" ] || continue
		while read -r lib; do
			[ -n "$lib" ] || continue
			path=$(_find_icd_lib "$json" "$lib")
			[ -n "$path" ] && [ -e "$path" ] || continue
			if [ "$(_elf_class "$path")" = "1" ]; then
				log "32-bit Vulkan driver found: $path"
				found=1
			fi
		done < <(grep -o '"library_path"[[:space:]]*:[[:space:]]*"[^"]*"' "$json" |
			sed 's/.*:[[:space:]]*"//; s/"$//')
	done

	if [ "$found" -eq 0 ]; then
		log "WARNING: no 32-bit Vulkan driver detected."
		log "WARNING: the Steam runtime container cannot provide GPU drivers - they come"
		log "WARNING: from the host. Lineage II is a 32-bit game, so it needs the 32-bit"
		log "WARNING: Vulkan driver for your GPU, e.g.:"
		log "WARNING:   Arch:   lib32-nvidia-utils / lib32-vulkan-radeon / lib32-vulkan-intel"
		log "WARNING:   Debian: nvidia-driver-libs:i386 / mesa-vulkan-drivers:i386"
		log "WARNING:   Fedora: vulkan-loader.i686 + mesa-vulkan-drivers.i686"
		log "WARNING: This check is not conclusive - continuing anyway."
	fi
	return 0
}

# Hard failures: missing these means nothing downstream can work.
preflight() {
	local missing=() py_ver avail

	for cmd in curl tar unzip; do
		command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
	done
	command -v python3 >/dev/null 2>&1 || missing+=("python3")

	if [ "${#missing[@]}" -gt 0 ]; then
		ui_error "Missing required program(s): ${missing[*]}

Please install them with your distribution's package manager and run Lightning-L2 again."
		return 1
	fi

	# umu is a Python zipapp and needs 3.10+.
	py_ver=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo "0.0")
	if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
		ui_error "Python $py_ver is too old - Lightning-L2 needs Python 3.10 or newer (it runs the game through umu-launcher, a Python program).

Please update python3 and try again."
		return 1
	fi
	log "python3 $py_ver OK"

	mkdir -p "$INSTALL_DIR"
	avail=$(df --output=avail -k "$INSTALL_DIR" 2>/dev/null | tail -n1 | tr -d ' ') || true
	if [ -n "$avail" ] && [ "$avail" -lt "$REQUIRED_FREE_KB" ] 2>/dev/null; then
		ui_error "Not enough free space in $INSTALL_DIR.

Lightning-L2 needs about $((REQUIRED_FREE_KB / 1024 / 1024))GB free for Proton, the Steam runtime and the Wine prefix (currently $((avail / 1024 / 1024))GB free). Free up space and try again."
		return 1
	fi

	check_vulkan32
	return 0
}
