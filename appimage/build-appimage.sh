#!/bin/bash
# Builds Lightning-L2-x86_64.AppImage from AppDir/.
# The AppImage ships shell scripts and icons only - no compiled code, so
# no glibc-version problem. Proton, the Steam runtime and the prefix are
# all fetched at runtime.
set -e
cd "$(dirname "$(readlink -f "$0")")"

APPDIR="AppDir"
CACHE=".build"
TOOL="$CACHE/appimagetool-x86_64.AppImage"
TOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
OUT="Lightning-L2-x86_64.AppImage"

# Icons come from the .deb tree, which stays the single source for them.
ICON_SRC="../packaging/usr/share/icons/hicolor"
rm -rf "$APPDIR/usr/share/icons"
mkdir -p "$APPDIR/usr/share/icons"
cp -r "$ICON_SRC" "$APPDIR/usr/share/icons/"
# appimagetool wants an icon at the AppDir root matching Icon=.
cp "$ICON_SRC/256x256/apps/lightning-l2.png" "$APPDIR/lightning-l2.png"

chmod 755 "$APPDIR/AppRun" "$APPDIR/opt/lightning-l2"/*.sh
chmod 644 "$APPDIR/opt/lightning-l2/lib"/*.sh

mkdir -p "$CACHE"
if [ ! -x "$TOOL" ]; then
	echo "Fetching appimagetool..."
	curl -fSL -o "$TOOL" "$TOOL_URL"
	chmod +x "$TOOL"
fi

# --appimage-extract-and-run so the build itself does not need FUSE.
ARCH=x86_64 "$TOOL" --appimage-extract-and-run "$APPDIR" "$OUT"
echo "Built $(dirname "$(readlink -f "$0")")/$OUT"
echo "If FUSE is missing on a player's system, it still runs with:"
echo "  ./$OUT --appimage-extract-and-run"
