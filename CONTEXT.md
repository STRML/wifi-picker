# Domain Context (`wifi-picker`)

Shared domain vocabulary and invariants for `wifi-picker`. See [docs/superpowers/specs/2026-11-20-wifi-picker-design.md](docs/superpowers/specs/2026-11-20-wifi-picker-design.md) for the original design rationale and failure matrix.

## Core Concepts

- **Scan Sample**: A single BSSID observation returned by CoreWLAN (SSID, BSSID, RSSI, security flag, saved-profile flag). Hidden networks (empty SSID) are ignored. Multiple BSSIDs for the same SSID merge into one network entry taking the strongest RSSI (tie-broken deterministically by `bssid <`), security from that strongest BSSID, and `known = true` if any BSSID is known.
- **Column**: One of three fixed-width side-by-side lists in the grid:
  1. **Hotspots** — SSIDs matching phone or mobile-hotspot naming patterns. Always wins over Known (the owner's saved iPhone belongs in Hotspots).
  2. **Known** — Non-hotspot SSIDs with a saved macOS network profile.
  3. **Other** — All remaining nearby SSIDs.
- **Slot**: A fixed row position in a column owned by one SSID for the duration of an open panel. Contents (signal bars, lock/checkmark, joining spinner, dimming) update in place; a slot never moves or changes column while the panel is open.
- **Freeze**: The once-per-open snapshot taken by `PickerSession` when the panel opens. Prunes networks unseen for more than 5 minutes (`pruneInterval = 300 s`), classifies remaining networks into the three columns, and sorts each column case-insensitively with UTF-8 tie-breaking.
- **Absorb**: Merging scan samples received while the panel is already open. Existing slots stay fixed (even if a network becomes Known while open); newly discovered SSIDs append to the bottom of their classified column in arrival order (`firstSeen`, tie-broken alphabetically).
- **Dimming**: While open, a slot whose SSID has not been seen for `>= 60 s` (`dimInterval`) stays in place at reduced opacity and ignores clicks. Tolerates incomplete single scans. If the SSID reappears, it undims in place.
- **Pruning**: Dropping SSIDs unseen for `> 300 s` (`pruneInterval`). Only happens on the next **Freeze** (next panel open), never while open.
- **Cache Freshness**: macOS scans periodically in the background and fires `scanCacheUpdated`. On panel open, the app reads the system scan cache immediately and only starts an active `scanForNetworks` if no cache update or scan has occurred within `120 s` (`cacheFreshness`).
- **Live Mode**: Active only while the panel is open. Subscribes to link-quality updates for the header stats row, reacts to `scanCacheUpdated`, and runs a 5 s clock to evaluate dimming. Stops completely on close so idle CPU is near zero.
- **Panel Lifecycle**: Explicit three-state lifecycle (`closed`, `opening`, `open`) owned by `PickerModel`. Opening reads the cache, freezes once, transitions to `open`, enters live mode, and triggers a scan if cache is stale.
- **Join Lifecycle**: Explicit modal/activity state (`idle`, `promptingPassword`, `joining`, `failed`) owned by `PickerModel`. Pressing Esc while prompting for a password dismisses the sheet and keeps the panel open; pressing Esc during an in-flight join closes the panel without cancelling the join (reopening while still joining continues showing the active join).
- **Environment Seam**: Single seam (`PickerEnvironment`) separating `WifiPickerCore` from macOS frameworks (`CoreWLAN`, `CoreLocation`, `SystemConfiguration`). Satisfied by three adapters: live macOS hardware (`MacWiFiEnvironment`), `--demo` (`DemoEnvironment`), and deterministic test fakes.
