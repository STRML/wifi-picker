#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$HOME/Applications/WifiPicker.app"

"$root/scripts/bundle.sh"

pkill -x WifiPicker || true
while pgrep -x WifiPicker >/dev/null; do sleep 0.1; done

mkdir -p "$HOME/Applications"
[ -e "$dest" ] && /usr/bin/trash "$dest"
ditto "$root/build/WifiPicker.app" "$dest"
/usr/bin/open "$dest"
echo "$dest"
