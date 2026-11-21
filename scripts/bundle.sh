#!/bin/bash
# Builds and signs build/WifiPicker.app.
#   SIGN_IDENTITY  codesign identity (default: the Apple Development identity)
#   UNIVERSAL=1    build arm64 + x86_64 instead of the host architecture
#   VERSION        CFBundleShortVersionString to stamp (default: the one in Info.plist)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
identity="${SIGN_IDENTITY:-Apple Development: Samuel Reed (Z7JP3ZX28A)}"
app="$root/build/WifiPicker.app"
build_args=(-c release)
[ "${UNIVERSAL:-0}" = 1 ] && build_args+=(--arch arm64 --arch x86_64)

cd "$root"
swift build "${build_args[@]}"
bin="$(swift build "${build_args[@]}" --show-bin-path)/WifiPicker"

[ -e "$app" ] && /usr/bin/trash "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/WifiPicker"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
if [ -n "${VERSION:-}" ]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$app/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "$(git rev-list --count HEAD)" "$app/Contents/Info.plist"
fi

codesign --force --options runtime --timestamp \
    --entitlements Resources/WifiPicker.entitlements \
    --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
entitlements="$(codesign -d --entitlements - "$app" 2>/dev/null)"
grep -q "com.apple.security.personal-information.location" <<<"$entitlements" \
    || { echo "location entitlement missing from signed app" >&2; exit 1; }

echo "$app"
