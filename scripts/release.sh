#!/bin/zsh
# Builds a universal (Apple silicon + Intel) release of Barlight and zips it
# for download: dist/Barlight-<version>.zip, plus its SHA-256.
#
# The app is ad-hoc signed, not notarized, so on first launch macOS asks the
# user to allow it in System Settings › Privacy & Security.
set -euo pipefail

ROOT="${0:A:h:h}"
SCRATCH="$HOME/Library/Caches/Barlight-release"
DIST="$ROOT/dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
APP="$DIST/Barlight.app"
ZIP="$DIST/Barlight-$VERSION.zip"

ARCHS=(--arch arm64 --arch x86_64)
swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c release $ARCHS
BIN="$(swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c release $ARCHS --show-bin-path)"

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Barlight" "$APP/Contents/MacOS/"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/"
cp "$ROOT/Resources/AppIcon.icns" "$ROOT/Resources/MenuBarIcon.pdf" "$APP/Contents/Resources/"
for bundle in "$BIN"/*.bundle(N); do cp -R "$bundle" "$APP/Contents/Resources/"; done

codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

# ditto keeps the bundle's structure and signature intact, unlike zip.
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$DIST" && shasum -a 256 "${ZIP:t}" | tee "${ZIP:t}.sha256")
lipo -info "$APP/Contents/MacOS/Barlight"
