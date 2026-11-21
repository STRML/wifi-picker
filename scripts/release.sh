#!/bin/bash
# Usage: scripts/release.sh <version>
# Builds a universal app signed with Developer ID, notarizes it with `asc`,
# staples the ticket and writes build/WifiPicker-<version>.zip.
set -euo pipefail

version="${1:?usage: scripts/release.sh <version>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
identity="${SIGN_IDENTITY:-Developer ID Application: Samuel Reed (HYBSCYDCMB)}"
app="$root/build/WifiPicker.app"
upload="$root/build/WifiPicker-$version-notarize.zip"
zip="$root/build/WifiPicker-$version.zip"

SIGN_IDENTITY="$identity" UNIVERSAL=1 VERSION="$version" "$root/scripts/bundle.sh"
lipo -archs "$app/Contents/MacOS/WifiPicker"

for f in "$upload" "$zip"; do [ -e "$f" ] && /usr/bin/trash "$f"; done
ditto -c -k --keepParent "$app" "$upload"
asc notarization submit --file "$upload" --wait --timeout 45m --output table
/usr/bin/trash "$upload"

asc notarization staple --file "$app" --confirm
asc notarization validate --file "$app"
spctl --assess --type execute --verbose=2 "$app"

ditto -c -k --keepParent "$app" "$zip"
shasum -a 256 "$zip"
echo "$zip"
