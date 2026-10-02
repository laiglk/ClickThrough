#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash scripts/test.sh
bash scripts/build.sh

APP="$PWD/ClickThrough.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCH=$(lipo -archs "$APP/Contents/MacOS/ClickThrough" | tr ' ' '-')
RELEASE_DIR="$PWD/dist/release"
ARCHIVE="ClickThrough-${VERSION}-${ARCH}.zip"
mkdir -p "$RELEASE_DIR"
codesign --verify --deep --strict "$APP"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --keepParent "$APP" "$RELEASE_DIR/$ARCHIVE"
cd "$RELEASE_DIR"
shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt
printf 'Archive prête : %s/%s\n' "$RELEASE_DIR" "$ARCHIVE"
