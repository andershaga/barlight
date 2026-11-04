#!/bin/zsh
# Builds Barlight.app without Xcode.
# Build products live outside the project so cloud sync doesn't upload them.
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIG="${1:-debug}"
SCRATCH="$HOME/Library/Caches/Barlight-build"
APP="$SCRATCH/Barlight.app"

swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c "$CONFIG"
BIN="$(swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Barlight" "$APP/Contents/MacOS/"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/"
cp "$ROOT/Resources/AppIcon.icns" "$ROOT/Resources/MenuBarIcon.pdf" "$APP/Contents/Resources/"
for bundle in "$BIN"/*.bundle(N); do cp -R "$bundle" "$APP/Contents/Resources/"; done

codesign --force --sign - "$APP"
echo "$APP"
