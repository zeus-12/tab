#!/usr/bin/env bash
# Builds the SwiftPM executable and assembles a runnable Tab.app bundle.
# Usage: scripts/build-app.sh [debug|release]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="$ROOT/Tab.app"

echo "▸ Building Tab ($CONFIG)…"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/Tab"
if [[ ! -x "$BIN" ]]; then
    echo "✗ Build product not found at $BIN" >&2
    exit 1
fi

echo "▸ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tab"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "▸ Ad-hoc code signing…"
codesign --force --sign - "$APP"

echo "✓ Built $APP"
echo "  Run it with:  open \"$APP\""
echo "  Then grant Accessibility in System Settings ▸ Privacy & Security ▸ Accessibility."
