#!/bin/bash
# Builds and signs dist/MajesDisk.app without Xcode. Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CFG="${1:-release}"
swift build -c "$CFG" --product MajesDisk
swift build -c "$CFG" --product majes-helper
BIN=$(swift build -c "$CFG" --show-bin-path)
if [ ! -f Resources/AppIcon.icns ] && [ -f scripts/make-icon.swift ]; then
  rm -rf dist/AppIcon.iconset && mkdir -p dist
  swift scripts/make-icon.swift dist/AppIcon.iconset && iconutil -c icns dist/AppIcon.iconset -o Resources/AppIcon.icns
fi
APP=dist/MajesDisk.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/MajesDisk" "$APP/Contents/MacOS/"
cp "$BIN/majes-helper" "$APP/Contents/Helpers/"
cp Resources/Info.plist "$APP/Contents/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
ID="${MAJESDISK_SIGN_IDENTITY:--}"
codesign --force --options runtime --timestamp=none -s "$ID" "$APP/Contents/Helpers/majes-helper"
codesign --force --options runtime --timestamp=none -s "$ID" "$APP"
codesign --verify --strict "$APP"
echo "$PWD/$APP"
