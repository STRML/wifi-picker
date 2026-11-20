# wifi-picker design

wifi-picker replaces the macOS Wi-Fi menu with a menu bar panel that opens
instantly and never moves a row the user can see.

## Why

The system menu starts a scan when it opens and re-sorts rows as signal
readings arrive, so the row under the pointer changes just before a click. A
`scanForNetworks` call on this Mac took 12.96 s cold and 0.95 s warm (measured
from a command-line spike, not from Apple's menu). Reading the system's scan
cache took 66.6 ms from a signed app and returned 21 named networks.

## Goals

- Open with a full list in under 100 ms, read from the system scan cache.
- Show a grid with three columns at the default width.
- Keep every row in place while the panel is open. Nothing under the pointer shifts.
- Lay out the same set of networks the same way on every open.
- Join a network with one click, with password entry when needed.
- Feel native: vibrancy material, SF Symbols, hover and pressed states, and full
  keyboard navigation (arrow keys move across the grid, Return joins, Esc closes).

## Non-goals

Personal Hotspot, Wi-Fi diagnostics, Network Locations, an 802.1X (enterprise)
join UI, and a hidden-network join UI. A footer link opens System Settings for
hidden networks.

## Anti-goals

- Background scanning on a timer. A scan hops channels and stalls the live
  connection, including ssh sessions to the Studios.
- Any animation that moves an existing row.

## Constraints

- CoreWLAN returns `nil` SSIDs unless the process is a signed app bundle with
  Location authorization. The app asks once. When access is denied, it shows an
  empty state with a button that opens System Settings.
- The scan cache holds one entry per BSSID (273-310 entries here, 155 from one
  fresh scan). Each row groups the BSSIDs of one SSID and shows the strongest.

## Approaches

| Approach | Trade-off | Verdict |
|---|---|---|
| AppKit `NSStatusItem` plus a borderless `NSPanel` hosting SwiftUI | Full control of open and close, growth anchored at the top, key focus for the password field | Picked |
| SwiftUI `MenuBarExtra(.window)` | Less code, but no reliable per-open hook and no control of window growth | Rejected |
| `NSMenu` | Native look, but redraws poorly while open and has no grid | Rejected |

## Layout rules

1. The grid has two sections, in order: Known (the SSID has a saved profile) and
   Other. The current network is marked in place with an accent tint and a
   checkmark. It does not move to the top.
2. Within a section, SSIDs sort case-insensitively, with ties broken by raw bytes.
3. The grid fills row by row, three columns wide.
4. When the panel opens, the layout freezes. Every visible SSID owns a slot.
5. While the panel is open:
   - a slot's contents (signal bars, lock, connected state) update in place;
   - an SSID that drops out keeps its slot and dims, but only after it has been
     missing for 60 s. Single scans are incomplete (two back-to-back scans
     returned 26 and 155 BSSIDs), so one miss must not dim a row;
   - a newly seen SSID goes into a trailing New section in arrival order, so
     nothing above it moves;
   - the panel grows downward only, anchored under the status item. Past a
     maximum height the grid scrolls and the header stays fixed.
6. The next open rebuilds the layout. New SSIDs take their alphabetical slot, and
   SSIDs unseen for 5 minutes drop out.
7. Controls (Wi-Fi power, Rescan, current network details) sit in the fixed
   header above the grid, so growth never moves them.
8. The header and every cell have fixed heights. A spinner, "Scan failed", or a
   join error replaces text inside a fixed-height status line; it never adds a
   line. Cell contents truncate with an ellipsis and never wrap.
9. Across opens, rule 6 can move cells: one new SSID in a row-major grid moves
   every later cell by one position. This is Claude's call. The guarantee is
   that nothing moves while the panel is open and that the order is predictable
   (alphabetical) between opens.

The core invariant, tested as a property test on `LayoutEngine`: after the
freeze, any sequence of store updates leaves the SSID in every existing slot
unchanged and only appends slots.

## Data flow

    system scan cache ─▶ NetworkStore ─────────▶ LayoutEngine ─▶ GridView
          ▲              (grouped by SSID,       (pure function,   (SwiftUI)
          │               lastSeen per SSID)      frozen per open)
          │                   ▲
    CWEventDelegate      panel open starts one scan on a background queue
    scanCacheUpdated

## Joining

1. The user clicks a row.
2. If the SSID has a saved profile, the app calls `associate(to:password:)` with
   a `nil` password.
3. If the network is open, the app associates directly.
4. If the network is secured and has no saved password, a password sheet opens
   over the bottom of the panel. It overlays the grid, so no row reflows.
5. Errors show in the header.

## Failure matrix

| State or input | What the app does | How it can fail | What the user sees |
|---|---|---|---|
| Location not determined | Requests access on first open | User dismisses the prompt | Empty state with "Allow in System Settings" |
| Location denied | Skips scanning | SSIDs are `nil` | The same empty state |
| Wi-Fi off | Skips scanning | Scan throws | Header toggle reads Off; grid reads "Wi-Fi is off" |
| Cache empty on open | Shows an empty grid and starts a scan | Scan takes 13 s | Spinner in the header; rows arrive in New |
| Scan throws while open | Keeps the current layout | CoreWLAN error | Header reads "Scan failed"; Rescan stays enabled |
| SSID missing from one scan | Keeps the slot, undimmed | Not applicable | No change |
| SSID missing for 60 s while open | Keeps the slot, dimmed | Not applicable | Dimmed row that ignores clicks |
| Status text changes (spinner, error) | Replaces text in the fixed status line | Not applicable | Grid does not move |
| SSID appears while open | Appends it to New | Not applicable | Row at the end |
| One SSID on several bands | Merges into one row with the strongest RSSI | Not applicable | One row |
| SSID is `nil` (hidden network) | Excludes it | Not applicable | Not shown |
| One SSID seen as both open and secured | Groups by SSID; takes security from the strongest BSSID | Not applicable | One row |
| Join a saved network whose password is not in the keychain | Association throws | Auth error | Password sheet opens |
| Join with a wrong password | Association throws | Auth error | Sheet reads "Wrong password" |
| Click while another join runs | Ignores the second click | Not applicable | Spinner on the joining row |
| Panel closes mid-scan | Scan finishes into the store | Not applicable | Next open shows the results |
| SSID unseen for over 5 minutes | Drops it at the next open | Not applicable | Row is gone |
| More networks than fit | Grid scrolls | Not applicable | Scrollbar; header stays fixed |
