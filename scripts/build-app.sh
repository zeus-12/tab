#!/usr/bin/env bash
# Builds the SwiftPM executable and assembles a runnable Tab.app bundle.
# Usage: scripts/build-app.sh [debug|release]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="$ROOT/Tab.app"

# UNIVERSAL=1 builds a fat arm64+x86_64 binary (for distributed releases).
ARCH_FLAGS=""
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS="--arch arm64 --arch x86_64"
fi

echo "▸ Building Tab ($CONFIG${ARCH_FLAGS:+, universal})…"
swift build -c "$CONFIG" $ARCH_FLAGS

BIN="$(swift build -c "$CONFIG" $ARCH_FLAGS --show-bin-path)/Tab"
if [[ ! -x "$BIN" ]]; then
    echo "✗ Build product not found at $BIN" >&2
    exit 1
fi

echo "▸ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tab"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Prefer a stable self-signed identity (see scripts/setup-signing.sh) so macOS
# keeps permission grants across rebuilds. Fall back to ad-hoc otherwise.
# Use the stable self-signed identity if present (note: NOT `-v`, which filters
# out untrusted self-signed certs — ours is intentionally untrusted, which is
# fine for signing and for keeping TCC grants stable across rebuilds).
SIGN_ID="${TAB_SIGN_IDENTITY:-Tab Dev}"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
    echo "▸ Signing with '$SIGN_ID'…"
    codesign --force --sign "$SIGN_ID" "$APP"
else
    echo "▸ Ad-hoc signing (run scripts/setup-signing.sh for stable permissions)…"
    codesign --force --sign - "$APP"
fi

echo "✓ Built $APP"
echo "  Run it with:  open \"$APP\""
echo "  Then grant Accessibility in System Settings ▸ Privacy & Security ▸ Accessibility."
