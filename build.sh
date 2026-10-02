#!/bin/sh
# Build MiniQuit.app with the system Swift compiler. No Xcode project needed.
#   ./build.sh          build in repo
#   ./build.sh install  build + install to /Applications + launch
set -eu
cd "$(dirname "$0")"
APP="MiniQuit.app"
DEST="/Applications/MiniQuit.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc main.swift -o "$APP/Contents/MacOS/MiniQuit" \
    -framework AppKit -framework ServiceManagement -O
cp Info.plist "$APP/Contents/Info.plist"

# --- icon: render 1024px mark, downscale into an .iconset, compile to .icns ---
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
"$APP/Contents/MacOS/MiniQuit" --genicon "$TMP/icon_1024.png"

mkdir -p "$TMP/MiniQuit.iconset"
icon() { # icon <point-size> <file-name>
    sips -z "$1" "$1" "$TMP/icon_1024.png" --out "$TMP/MiniQuit.iconset/$2" >/dev/null
}
icon 16    "icon_16x16.png"
icon 32    "icon_16x16@2x.png"
icon 32    "icon_32x32.png"
icon 64    "icon_32x32@2x.png"
icon 128   "icon_128x128.png"
icon 256   "icon_128x128@2x.png"
icon 256   "icon_256x256.png"
icon 512   "icon_256x256@2x.png"
icon 512   "icon_512x512.png"
icon 1024  "icon_512x512@2x.png"
iconutil -c icns "$TMP/MiniQuit.iconset" -o "$APP/Contents/Resources/MiniQuit.icns"

codesign --force --deep --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "install" ]; then
    pkill -x MiniQuit 2>/dev/null || true
    sleep 0.3
    # ditto merges in place — no delete, bundle path/identifier stay stable for the login item.
    ditto "$APP" "$DEST"
    echo "Installed $DEST"
    open "$DEST"
fi
