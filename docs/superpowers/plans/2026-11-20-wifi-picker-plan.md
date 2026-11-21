# wifi-picker implementation plan

Build the app described in `docs/superpowers/specs/2026-11-20-wifi-picker-design.md`.
Read that design first; this plan says how and in what order.

## Toolchain

- Swift 6.4, Xcode 27.2, macOS 27.2, arm64. SwiftPM only, no `.xcodeproj`.
- Tests use Swift Testing (`import Testing`).
- Sign with `Apple Development: Samuel Reed (Z7JP3ZX28A)`, hardened runtime, and
  the entitlement `com.apple.security.personal-information.location`. Without
  that entitlement, Location Services never answers (found in the spike).
- Bundle ID `com.strml.wifi-picker`. `LSUIElement` true. `LSMinimumSystemVersion`
  14.0. Info.plist carries `NSLocationUsageDescription` and
  `NSLocationWhenInUseUsageDescription`.

## Layout of the repo

    wifi-picker/
    ├── Package.swift
    ├── Sources/
    │   ├── WifiPickerCore/        pure logic, no AppKit, no CoreWLAN
    │   │   ├── ScanSample.swift       one BSSID reading (ssid, rssi, channel band, security, known)
    │   │   ├── NetworkStore.swift     merges samples by SSID, tracks lastSeen, takes a clock
    │   │   ├── HotspotClassifier.swift  pure: does an SSID look like a phone hotspot
    │   │   ├── LayoutEngine.swift     freeze(store, now) -> FrozenLayout (three columns); absorb appends only
    │   │   ├── PickerSession.swift    owns store + layout; opens once, after the first cache read
    │   │   └── JoinPolicy.swift       pure: when to ask for a password, what an error means
    │   └── WifiPicker/            the app
    │       ├── main.swift             NSApplication, accessory policy
    │       ├── StatusItemController.swift  NSStatusItem, opens and closes the panel
    │       ├── PickerPanel.swift      borderless NSPanel, NSVisualEffectView, anchored under the item
    │       ├── WiFiService.swift      CoreWLAN: cache read, scan on a background queue, events, join
    │       ├── LocationGate.swift     CLLocationManager authorization
    │       └── Views/                 SwiftUI: HeaderView, GridView, CellView, PasswordSheet
    ├── Tests/WifiPickerCoreTests/
    ├── Resources/Info.plist, Resources/WifiPicker.entitlements
    └── scripts/
        ├── bundle.sh          swift build -c release, assemble .app, codesign, verify signature
        └── install.sh         bundle.sh, copy to ~/Applications/WifiPicker.app, relaunch it

## Core types

- `ScanSample { ssid: String; bssid: String; rssi: Int; band: Band; secure: Bool; known: Bool }`.
  Samples with a nil SSID never reach the core: `WiFiService` drops them.
- `NetworkStore` keeps one `NetworkEntry` per SSID: strongest RSSI from the
  latest batch that contained it, `secure` and `band` from that strongest
  sample, `known`, `firstSeen`, `lastSeen`. `ingest(samples, at:)` merges a
  batch. A batch never removes entries. `prune(olderThan:)` drops entries unseen
  for that long; only `LayoutEngine.freeze` calls it (5 minutes).
- `FrozenLayout` holds `columns: [LayoutColumn]`, each with ordered `slots: [SSID]`.
  Columns, left to right: `.hotspots`, `.known`, `.other`. `cell(ssid)` returns
  live data plus a `dimmed` flag (unseen for 60 s or more).
- `HotspotClassifier.isHotspot(ssid)` matches phone and mobile-hotspot names
  (iPhone, iPad, Galaxy, Pixel, AndroidAP, Android, OnePlus, Redmi, Xiaomi, Moto,
  Hotspot, MiFi, Jetpack, and the "<name>'s <device>" possessive) case-insensitively.
  Hotspot wins over Known.
- `LayoutEngine.freeze(store, now:)` prunes, assigns each entry a column, and sorts
  each column by `localizedCaseInsensitiveCompare` with raw bytes as a tiebreak.
  `layout.absorb(store)` appends any SSID not yet in a slot to the bottom of the
  column it classifies into, in `firstSeen` order, and changes nothing else.
- `PickerSession` owns the store and the layout. `open(at:)` freezes once, only
  after the first cache ingest (or an explicit `markCacheLoaded()` after a
  timeout), and refuses while already open. Ingests while open absorb. Nothing
  else calls `freeze`.
- `FrozenLayout.move(from:_:)` implements the keyboard rules: up and down inside a
  column, left and right to the same row index in the adjacent filled column.

## Tests (write first, all red before the code)

Every failure-matrix row in the design that involves core logic gets a test.
The rows covering Location, Wi-Fi power and joining are app-level and are
checked in the real-app verification below.

1. Property test, seeded random generator, 500 iterations: build a store, freeze,
   then apply 1-30 random batches (new SSIDs, missing SSIDs, RSSI changes,
   known flips) with `absorb` after each. Invariant: for every column, the slot
   list before every absorb is a prefix of the list after it, and the column of
   every existing slot never changes.
2. Determinism: freezing two stores holding the same entries in different
   insertion orders gives identical layouts.
3. Sort: mixed case, accents, emoji and an identical-ignoring-case pair sort
   stably.
4. Merge: three BSSIDs of one SSID give one entry with the strongest RSSI.
5. Dimming: an entry missing from one batch is not dimmed; missing for 60 s is.
6. Prune: an entry unseen for over 5 minutes is gone after the next freeze, and
   still present (dimmed) in an existing frozen layout.
7. Known flip while open: an SSID that becomes known stays in its `.other` slot
   until the next freeze.
8. Hotspot classification: the listed names, both apostrophes and case variants
   are hotspots; ordinary names are not; hotspot wins over Known.
9. Arrivals append to the bottom of their own column in arrival order and never
   touch another column.
10. Session: open is refused until the first cache ingest; a second open while open
    never refreezes; a random open/ingest/close sequence never changes a column's
    slots while open.
11. Keyboard navigation: up and down clamp inside a column; left and right keep the
    row index, clamp to the shorter column and skip empty columns.

## App behaviour (build after the core is green)

- `WiFiService` owns one serial queue. On launch and on every
  `scanCacheUpdated` event it reads `cachedScanResults()` and ingests it. It
  never scans on a timer. `scan()` runs `scanForNetworks(withSSID: nil)` on
  the queue and ingests the result; a second call while one runs is a no-op.
  The current SSID comes from `interface.ssid()`.
- Opening the panel: wait (at most 1.5 s) for the first cache read, freeze the
  layout from the in-memory store through `PickerSession.open`, show the panel,
  then re-read `cachedScanResults()` on the service queue and call `scan()`.
  The cache read costs about 67 ms, so it never runs on the main thread, and the
  `scanCacheUpdated` event alone is not relied on (it fired twice in 180 s).
- `PickerPanel` is a non-activating borderless `NSPanel` that can become key (for
  the password field). Its top edge stays pinned under the status item. Its
  height grows only, to at most 70% of the screen's visible height, after which
  the grid scrolls inside a `ScrollView`. It closes on Esc, on a click outside,
  and on a second click of the status item.
- Grid: three fixed-width columns (Hotspots, Known, Other), each with a 26 pt
  header label and 34 pt rows, inside one shared vertical `ScrollView`. Panel
  height is header + tallest column, capped at 70% of the visible height. An empty
  column shows a dim "None nearby" line at cell height.
- Cells: fixed height 30 pt, fixed width (panel width 600 pt, 3 columns, minus
  the legacy scroller width so rows fit with or without a scroller).
  Contents: name (truncates in the middle), lock glyph, signal bars glyph
  (`wifi` SF Symbol with variable value from RSSI), checkmark for the current
  network. Hover highlight with `.quaternary` fill; pressed state; dimmed at
  40% opacity.
- Header: fixed height. Wi-Fi power toggle, current network name and status
  line (one line, fixed height), Rescan button with a spinner that replaces its
  glyph in place.
- Keyboard: arrows move a focus ring (up and down inside a column, left and right
  to the same row in the adjacent column); Return joins; Esc closes.
- Joining: in the design's order. The password sheet overlays the bottom of the
  panel and never changes the grid's frames. Join runs on the service queue;
  the joining cell shows a spinner in place of the bars glyph.
- Location not authorized or Wi-Fi off: the grid area shows a centered message
  with one button (open System Settings, or turn Wi-Fi on).
- The status item icon is the `wifi` SF Symbol, with its variable value set
  from the current RSSI, and `wifi.slash` when Wi-Fi is off.

## Verification on the real Mac

`scripts/verify.sh` (run by the coordinator, not the builder):

1. `scripts/install.sh`.
2. Open the panel from a test hook: the app accepts a `--open-panel` launch
   argument and a `--dump-frames <file>` argument that writes every cell's
   SSID, column name and frame as JSON after each layout pass (JSON Lines, with a
   `reason` of `layout` or `scan-finished`).
3. Wait for one scan to complete, dump frames, and compare against the dump
   taken at open: every SSID present at open must keep an identical frame.
4. Take a screenshot of the panel with `screencapture -l <windowid>`.

## Commits

One commit per step: core and tests, app shell and panel, views, joining,
scripts, then the session fix, the three-column layout and the docs. Subjects use
`feat:`, `fix:`, `test:`, `docs:` or `chore:`.
