# wifi-picker design

wifi-picker replaces the macOS Wi-Fi menu with a menu bar panel that opens
instantly and never moves a row the user can see.

## Why

The system menu starts a scan when it opens and re-sorts rows as signal
readings arrive, so the row under the pointer changes just before a click. A
`scanForNetworks` call on this Mac took 12.96 s cold and 0.95 s warm (measured
from a command-line spike, not from Apple's menu). Reading the system's scan
cache took 66.6 ms from a signed app and returned 21 named networks.

Later spike facts, measured from the signed app:

- `scanCacheUpdated` fired twice in 180 s with no app-initiated scan, so the cache
  alone does not refresh fast enough to follow.
- A fresh scan found 17 SSIDs, 16 of which were already in the cache.
- The first scan took 12.59 s; repeat scans took 0.05 s.

## Goals

- Open with a full list in under 100 ms, read from the system scan cache.
- Show three columns side by side: Hotspots, Known, Other. This is the macOS
  Wi-Fi menu's grouping, laid out in columns instead of stacked.
- Keep every row in place while the panel is open. Nothing under the pointer shifts.
- Lay out the same set of networks the same way on every open.
- Freeze the layout exactly once per open, after the first cache read.
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
- Instant Hotspot (waking a nearby iPhone's hotspot over Bluetooth) is private
  API. The Hotspots column only shows hotspots that are already broadcasting.

## Approaches

| Approach | Trade-off | Verdict |
|---|---|---|
| AppKit `NSStatusItem` plus a borderless `NSPanel` hosting SwiftUI | Full control of open and close, growth anchored at the top, key focus for the password field | Picked |
| SwiftUI `MenuBarExtra(.window)` | Less code, but no reliable per-open hook and no control of window growth | Rejected |
| `NSMenu` | Native look, but redraws poorly while open and has no grid | Rejected |

## Layout rules

1. The grid has three fixed-width columns, left to right: Hotspots, Known, Other.
   Each column has a fixed-height header label and is a vertical list. The current
   network is marked in place with an accent tint and a checkmark. It does not
   move to the top.
2. Column membership is decided at freeze:
   - an SSID is a hotspot when its name matches a phone or mobile-hotspot pattern
     (case-insensitive: iPhone, iPad, Galaxy, Pixel, AndroidAP, Android, OnePlus,
     Redmi, Xiaomi, Moto, Hotspot, MiFi, Jetpack, or the "<name>'s <device>"
     possessive with a straight or curly apostrophe);
   - otherwise it is Known when it has a saved profile;
   - otherwise it is Other.

   Hotspot wins over Known: the owner's own iPhone is a saved network but belongs
   in Hotspots. `HotspotClassifier` is a pure function in the core.
3. Within a column, SSIDs sort case-insensitively, with ties broken by raw bytes.
4. When the panel opens, the layout freezes once, after the first cache read has
   landed. Every visible SSID owns a slot. Nothing calls freeze while the panel is
   open; the session object that owns the layout refuses a second open.
5. While the panel is open:
   - a slot's contents (signal bars, lock, connected state) update in place;
   - an SSID that drops out keeps its slot and dims, but only after it has been
     missing for 60 s. Single scans are incomplete (two back-to-back scans
     returned 26 and 155 BSSIDs), so one miss must not dim a row;
   - a newly seen SSID appends to the bottom of its own column, in arrival order.
     Appending in one column never moves a cell in another column;
   - an SSID that becomes known while open stays in its column;
   - the panel grows downward only, anchored under the status item. Its height is
     the header plus the tallest column. Past 70% of the visible screen height one
     shared vertical scroll view moves all three columns and the header stays fixed.
6. The next open rebuilds the layout. New SSIDs take their alphabetical slot, and
   SSIDs unseen for 5 minutes drop out.
7. Controls (Wi-Fi power, Rescan, current network details) sit in the fixed
   header above the grid, so growth never moves them.
8. The header, every column header and every cell have fixed heights. A spinner,
   "Scan failed", or a join error replaces text inside a fixed-height status line;
   it never adds a line. Cell contents truncate with an ellipsis and never wrap.
   An empty column shows a dim one-line "None nearby" placeholder at cell height.
9. Across opens, rule 6 can move cells: one new SSID in a column moves every later
   cell in that column by one position. This is Claude's call. The guarantee is
   that nothing moves while the panel is open and that the order is predictable
   (alphabetical) between opens.
10. Keyboard: up and down move within a column. Left and right move to the same
    row index in the adjacent column, clamped to its last cell, skipping empty
    columns.

The core invariant, tested as a property test on `LayoutEngine` and as a state
test on `PickerSession`: after the freeze, any sequence of store updates leaves
the SSID in every existing slot unchanged, keeps its column, and only appends to
the bottom of columns.

## Data flow

    system scan cache ─▶ PickerSession ────────▶ GridView
          ▲              (NetworkStore +        (SwiftUI, three columns)
          │               LayoutEngine freeze,
          │               once per open)
    CWEventDelegate           ▲
    scanCacheUpdated    panel open waits for the first cache read, then re-reads
                        the cache on the service queue and starts one scan

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
| Cache not read yet at open (launch) | Waits up to 1.5 s for the first cache read, then freezes | Cache read never arrives | Panel opens empty after the wait; rows append to their columns |
| Cache empty on open | Shows empty columns and starts a scan | Scan takes 13 s | Spinner in the header; rows arrive at the bottom of their columns |
| Open requested while already open | Ignores it; the layout is not frozen again | A second freeze would reorder cells | No change |
| Scan throws while open | Keeps the current layout | CoreWLAN error | Header reads "Scan failed"; Rescan stays enabled |
| SSID missing from one scan | Keeps the slot, undimmed | Not applicable | No change |
| SSID missing for 60 s while open | Keeps the slot, dimmed | Not applicable | Dimmed row that ignores clicks |
| Status text changes (spinner, error) | Replaces text in the fixed status line | Not applicable | Grid does not move |
| SSID appears while open | Appends it to the bottom of its own column | Not applicable | Cell at the end of its column; other columns unchanged |
| SSID becomes known while open | Keeps its column | Not applicable | No change |
| Known network is a phone hotspot | Hotspot wins over Known | Not applicable | Listed under Hotspots |
| A column has no networks | Shows a "None nearby" placeholder | Not applicable | Dim one-line placeholder |
| One SSID on several bands | Merges into one row with the strongest RSSI | Not applicable | One row |
| SSID is `nil` (hidden network) | Excludes it | Not applicable | Not shown |
| One SSID seen as both open and secured | Groups by SSID; takes security from the strongest BSSID | Not applicable | One row |
| Join a saved network whose password is not in the keychain | Association throws | Auth error | Password sheet opens |
| Join with a wrong password | Association throws | Auth error | Sheet reads "Wrong password" |
| Click while another join runs | Ignores the second click | Not applicable | Spinner on the joining row |
| Panel closes mid-scan | Scan finishes into the store | Not applicable | Next open shows the results |
| SSID unseen for over 5 minutes | Drops it at the next open | Not applicable | Row is gone |
| More networks than fit | The three columns scroll together | Not applicable | Scrollbar; header stays fixed |
