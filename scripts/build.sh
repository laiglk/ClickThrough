#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
swift build -c release --product ClickThrough --disable-sandbox --cache-path "$PWD/.build/cache"
BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox --cache-path "$PWD/.build/cache")"
APP="$PWD/ClickThrough.app"
LEGACY_APP="$PWD/dist/ClickThrough.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ClickThrough" "$APP/Contents/MacOS/ClickThrough"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
swift scripts/make-icon.swift "$PWD/.build/ClickThrough.iconset" "$APP/Contents/Resources/AppIcon.icns"
# Set SIGN_IDENTITY to a Developer ID identity for a distributable signed build.
codesign --force --sign "${SIGN_IDENTITY:--}" --options runtime "$APP"
codesign --verify --strict "$APP"
mkdir -p "$PWD/dist"
ditto "$APP" "$LEGACY_APP"
printf 'Application prête : %s\n' "$APP"
