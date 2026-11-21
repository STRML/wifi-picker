#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
identity="Apple Development: Samuel Reed (Z7JP3ZX28A)"
app="$root/build/WifiPicker.app"

cd "$root"
swift build -c release
bin="$(swift build -c release --show-bin-path)/WifiPicker"

[ -e "$app" ] && /usr/bin/trash "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/WifiPicker"
cp Resources/Info.plist "$app/Contents/Info.plist"

codesign --force --options runtime \
    --entitlements Resources/WifiPicker.entitlements \
    --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
codesign -d --entitlements - "$app" 2>/dev/null | grep -q "com.apple.security.personal-information.location" \
    || { echo "location entitlement missing from signed app" >&2; exit 1; }

echo "$app"
