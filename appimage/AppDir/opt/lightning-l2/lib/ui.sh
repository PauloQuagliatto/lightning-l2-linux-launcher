#!/bin/bash
# Dialog shim: use whatever the host already has, bundle nothing.
#
# Bundling zenity into the AppImage means dragging in GTK3 plus
# gdk-pixbuf loaders, GIO modules and theme data - the classic AppImage
# trap, and it breaks differently on every host. So: host zenity, else
# kdialog (already there on KDE), else yad, else plain terminal prompts,
# which work because the .desktop runs with Terminal=true.

if [ -z "${UI_BACKEND:-}" ]; then
	UI_BACKEND=tty
	if [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
		for _ui_cand in zenity kdialog yad; do
			if command -v "$_ui_cand" >/dev/null 2>&1; then
				UI_BACKEND="$_ui_cand"
				break
			fi
		done
		unset _ui_cand
	fi
fi

ui_info() {
	case "$UI_BACKEND" in
		zenity) zenity --info --title="Lightning-L2" --text="$1" 2>/dev/null || true ;;
		kdialog) kdialog --title "Lightning-L2" --msgbox "$1" 2>/dev/null || true ;;
		yad) yad --info --title="Lightning-L2" --text="$1" --button=OK 2>/dev/null || true ;;
		*) echo "[Lightning-L2] $1" ;;
	esac
}

ui_error() {
	echo "[Lightning-L2] ERROR: $1" >&2
	case "$UI_BACKEND" in
		zenity) zenity --error --title="Lightning-L2" --text="$1" 2>/dev/null || true ;;
		kdialog) kdialog --title "Lightning-L2" --error "$1" 2>/dev/null || true ;;
		yad) yad --error --title="Lightning-L2" --text="$1" --button=OK 2>/dev/null || true ;;
	esac
}

# ui_question TEXT [OK_LABEL] [CANCEL_LABEL] - 0 = yes.
ui_question() {
	local text="$1" ok="${2:-Yes}" cancel="${3:-No}" answer
	case "$UI_BACKEND" in
		zenity)
			zenity --question --title="Lightning-L2" --text="$text" \
				--ok-label="$ok" --cancel-label="$cancel" 2>/dev/null
			;;
		kdialog)
			kdialog --title "Lightning-L2" --yes-label "$ok" --no-label "$cancel" \
				--yesno "$text" 2>/dev/null
			;;
		yad)
			yad --question --title="Lightning-L2" --text="$text" \
				--button="$cancel:1" --button="$ok:0" 2>/dev/null
			;;
		*)
			echo
			echo "[Lightning-L2] $text"
			read -r -p "  [y] $ok / [n] $cancel : " answer
			[ "$answer" = "y" ] || [ "$answer" = "Y" ]
			;;
	esac
}

# Prints the chosen directory on stdout; non-zero if the player cancelled.
ui_select_dir() {
	local title="$1" dir
	case "$UI_BACKEND" in
		zenity) dir=$(zenity --file-selection --directory --title="$title" 2>/dev/null) ;;
		kdialog) dir=$(kdialog --title "$title" --getexistingdirectory "$HOME" 2>/dev/null) ;;
		yad) dir=$(yad --file --directory --title="$title" 2>/dev/null) ;;
		*)
			echo >&2
			echo "[Lightning-L2] $title" >&2
			read -r -e -p "  Path: " dir
			;;
	esac
	[ -n "$dir" ] || return 1
	echo "$dir"
}

# Consumes zenity-style progress lines on stdin. The non-GUI backends
# discard them, because progress() in config.sh already mirrored every
# line to stderr (and therefore to the terminal and the log file).
ui_progress() {
	case "$UI_BACKEND" in
		zenity)
			zenity --progress --title="Lightning-L2" --text="${1:-Starting...}" \
				--percentage=0 --auto-close --width=460 2>/dev/null
			;;
		yad)
			yad --progress --title="Lightning-L2" --text="${1:-Starting...}" \
				--percentage=0 --auto-close --width=460 2>/dev/null
			;;
		*) cat >/dev/null ;;
	esac
}
