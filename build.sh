#!/bin/sh
# Build MiniQuit.app with the system Swift compiler. No Xcode project needed.
set -eu
cd "$(dirname "$0")"
APP="MiniQuit.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc main.swift -o "$APP/Contents/MacOS/MiniQuit" -framework AppKit -O
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "Built $APP — run: open $APP"
