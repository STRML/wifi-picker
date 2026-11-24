import Foundation

public struct PickerSession: Sendable {
    public static let pruneInterval: TimeInterval = 300
    public static let dimInterval: TimeInterval = 60

    private var store = NetworkStore()
    public private(set) var columns: [LayoutColumn]
    public private(set) var isOpen = false

    public init() {
        columns = ColumnKind.allCases.map { LayoutColumn(kind: $0, slots: []) }
    }

    public var readingOrder: [String] { columns.flatMap(\.slots) }

    public var tallestColumnCount: Int { columns.map(\.slots.count).max() ?? 0 }

    public func slots(in kind: ColumnKind) -> [String] {
        columns[kind.rawValue].slots
    }

    public func column(of ssid: String) -> ColumnKind? {
        columns.first { $0.slots.contains(ssid) }?.kind
    }

    public func cell(for ssid: String, at now: Date) -> LayoutCell? {
        guard let entry = store.entries[ssid] else { return nil }
        let unseen = now.timeIntervalSince(entry.lastSeen)
        return LayoutCell(entry: entry, dimmed: unseen >= Self.dimInterval)
    }

    public mutating func ingest(_ samples: [ScanSample], at now: Date) {
        store.ingest(samples, at: now)
        guard isOpen else { return }
        absorb()
    }

    @discardableResult
    public mutating func open(at now: Date) -> Bool {
        guard !isOpen else { return false }
        store.prune(olderThan: Self.pruneInterval, now: now)
        freeze()
        isOpen = true
        return true
    }

    public mutating func close() {
        isOpen = false
    }

    public func move(from ssid: String?, _ direction: MoveDirection) -> String? {
        let filled = columns.filter { !$0.slots.isEmpty }
        guard let first = filled.first?.slots.first else { return nil }
        guard let ssid, let position = locate(ssid, in: filled) else { return first }
        switch direction {
        case .up:
            return filled[position.column].slots[max(0, position.row - 1)]
        case .down:
            let slots = filled[position.column].slots
            return slots[min(slots.count - 1, position.row + 1)]
        case .left:
            return neighbour(of: position, by: -1, in: filled)
        case .right:
            return neighbour(of: position, by: 1, in: filled)
        }
    }

    private mutating func freeze() {
        let grouped = Dictionary(grouping: store.entries.values, by: ColumnKind.classify)
        columns = ColumnKind.allCases.map { kind in
            let sorted = (grouped[kind] ?? []).sorted { Self.ssidPrecedes($0.ssid, $1.ssid) }
            return LayoutColumn(kind: kind, slots: sorted.map(\.ssid))
        }
    }

    private mutating func absorb() {
        let placed = Set(readingOrder)
        let arrivals = store.entries.values
            .filter { !placed.contains($0.ssid) }
            .sorted(by: Self.arrivedFirst)
        for entry in arrivals {
            columns[ColumnKind.classify(entry).rawValue].slots.append(entry.ssid)
        }
    }

    private func locate(_ ssid: String, in filled: [LayoutColumn]) -> (column: Int, row: Int)? {
        for (column, content) in filled.enumerated() {
            if let row = content.slots.firstIndex(of: ssid) { return (column, row) }
        }
        return nil
    }

    private func neighbour(of position: (column: Int, row: Int), by delta: Int, in filled: [LayoutColumn]) -> String {
        let target = position.column + delta
        guard filled.indices.contains(target) else { return filled[position.column].slots[position.row] }
        let slots = filled[target].slots
        return slots[min(position.row, slots.count - 1)]
    }

    private static func ssidPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        switch lhs.localizedCaseInsensitiveCompare(rhs) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
        }
    }

    private static func arrivedFirst(_ lhs: NetworkEntry, _ rhs: NetworkEntry) -> Bool {
        if lhs.firstSeen != rhs.firstSeen { return lhs.firstSeen < rhs.firstSeen }
        return ssidPrecedes(lhs.ssid, rhs.ssid)
    }
}
