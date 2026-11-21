import Foundation

public enum ColumnKind: Int, Sendable, CaseIterable {
    case hotspots
    case known
    case other

    static func classify(_ entry: NetworkEntry) -> ColumnKind {
        if HotspotClassifier.isHotspot(entry.ssid) { return .hotspots }
        return entry.known ? .known : .other
    }
}

public struct LayoutColumn: Sendable, Equatable {
    public let kind: ColumnKind
    public var slots: [String]
}

public struct LayoutCell: Sendable, Equatable {
    public let entry: NetworkEntry
    public let dimmed: Bool
}

public enum MoveDirection: Sendable {
    case left
    case right
    case up
    case down
}

public struct FrozenLayout: Sendable {
    public private(set) var columns: [LayoutColumn]
    private var snapshot: [String: NetworkEntry]

    fileprivate init(entries: [NetworkEntry]) {
        let grouped = Dictionary(grouping: entries, by: ColumnKind.classify)
        columns = ColumnKind.allCases.map { kind in
            let sorted = (grouped[kind] ?? []).sorted { LayoutEngine.ssidPrecedes($0.ssid, $1.ssid) }
            return LayoutColumn(kind: kind, slots: sorted.map(\.ssid))
        }
        snapshot = Dictionary(uniqueKeysWithValues: entries.map { ($0.ssid, $0) })
    }

    public var readingOrder: [String] { columns.flatMap(\.slots) }

    public var tallestColumnCount: Int { columns.map(\.slots.count).max() ?? 0 }

    public func slots(in kind: ColumnKind) -> [String] {
        columns[kind.rawValue].slots
    }

    public func column(of ssid: String) -> ColumnKind? {
        columns.first { $0.slots.contains(ssid) }?.kind
    }

    public mutating func absorb(_ store: NetworkStore) {
        let placed = Set(readingOrder)
        let arrivals = store.entries.values
            .filter { !placed.contains($0.ssid) }
            .sorted(by: Self.arrivedFirst)
        for entry in arrivals {
            snapshot[entry.ssid] = entry
            columns[ColumnKind.classify(entry).rawValue].slots.append(entry.ssid)
        }
    }

    public func cell(for ssid: String, in store: NetworkStore, now: Date) -> LayoutCell? {
        guard let entry = store.entries[ssid] ?? snapshot[ssid] else { return nil }
        let unseen = now.timeIntervalSince(entry.lastSeen)
        return LayoutCell(entry: entry, dimmed: unseen >= LayoutEngine.dimInterval)
    }

    public func move(from ssid: String?, _ direction: MoveDirection) -> String? {
        let filled = columns.filter { !$0.slots.isEmpty }
        guard let first = filled.first?.slots.first else { return nil }
        guard let ssid, let position = locate(ssid, in: filled) else { return first }
        switch direction {
        case .up: return filled[position.column].slots[max(0, position.row - 1)]
        case .down:
            let slots = filled[position.column].slots
            return slots[min(slots.count - 1, position.row + 1)]
        case .left: return neighbour(of: position, by: -1, in: filled)
        case .right: return neighbour(of: position, by: 1, in: filled)
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

    private static func arrivedFirst(_ lhs: NetworkEntry, _ rhs: NetworkEntry) -> Bool {
        if lhs.firstSeen != rhs.firstSeen { return lhs.firstSeen < rhs.firstSeen }
        return LayoutEngine.ssidPrecedes(lhs.ssid, rhs.ssid)
    }
}

public enum LayoutEngine {
    public static let pruneInterval: TimeInterval = 300
    public static let dimInterval: TimeInterval = 60

    public static func freeze(_ store: inout NetworkStore, now: Date) -> FrozenLayout {
        store.prune(olderThan: pruneInterval, now: now)
        return FrozenLayout(entries: Array(store.entries.values))
    }

    static func ssidPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        switch lhs.localizedCaseInsensitiveCompare(rhs) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
        }
    }
}
