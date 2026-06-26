#!/usr/bin/env bash
# Runs the swift-testing suite under SwiftPM.
#
# This project builds with the Command Line Tools (no full Xcode), where `swift test`
# can't find XCTest and doesn't wire up Testing.framework on its own. We point the
# compiler/linker at wherever Testing.framework lives under the active developer dir,
# add an rpath so it loads at runtime, and skip XCTest discovery with --disable-xctest.
set -euo pipefail

dev="$(xcode-select -p)"
fw="$(find "$dev" -maxdepth 4 -name 'Testing.framework' -type d 2>/dev/null | head -1)"
if [[ -z "$fw" ]]; then
  echo "Testing.framework not found under $dev — install a toolchain that ships swift-testing." >&2
  exit 1
fi
fwdir="$(dirname "$fw")"

exec swift test --disable-xctest \
  -Xswiftc -F -Xswiftc "$fwdir" \
  -Xlinker -F -Xlinker "$fwdir" \
  -Xlinker -rpath -Xlinker "$fwdir" "$@"
