import Foundation

public enum SectionKind: Int, Sendable, CaseIterable {
    case known
    case other
    case new
}

public struct LayoutSection: Sendable, Equatable {
    public let kind: SectionKind
    public var slots: [String]
}

public struct LayoutCell: Sendable, Equatable {
    public let entry: NetworkEntry
    public let dimmed: Bool
}

public struct GridRow: Sendable, Equatable {
    public let section: SectionKind
    public let startsSection: Bool
    public let slots: [String]
}

public enum MoveDirection: Sendable {
    case left
    case right
    case up
    case down
}

public struct FrozenLayout: Sendable {
    public private(set) var sections: [LayoutSection]
    private var snapshot: [String: NetworkEntry]

    fileprivate init(known: [NetworkEntry], other: [NetworkEntry]) {
        sections = [
            LayoutSection(kind: .known, slots: known.map(\.ssid)),
            LayoutSection(kind: .other, slots: other.map(\.ssid)),
            LayoutSection(kind: .new, slots: []),
        ]
        snapshot = Dictionary(uniqueKeysWithValues: (known + other).map { ($0.ssid, $0) })
    }

    public var readingOrder: [String] { sections.flatMap(\.slots) }

    public func slots(in kind: SectionKind) -> [String] {
        sections[kind.rawValue].slots
    }

    public mutating func absorb(_ store: NetworkStore) {
        let placed = Set(readingOrder)
        let arrivals = store.entries.values
            .filter { !placed.contains($0.ssid) }
            .sorted(by: Self.arrivedFirst)
        for entry in arrivals {
            snapshot[entry.ssid] = entry
            sections[SectionKind.new.rawValue].slots.append(entry.ssid)
        }
    }

    public func cell(for ssid: String, in store: NetworkStore, now: Date) -> LayoutCell? {
        guard let entry = store.entries[ssid] ?? snapshot[ssid] else { return nil }
        let unseen = now.timeIntervalSince(entry.lastSeen)
        return LayoutCell(entry: entry, dimmed: unseen >= LayoutEngine.dimInterval)
    }

    public func rows(columns: Int) -> [GridRow] {
        let width = max(1, columns)
        return sections.flatMap { section in
            stride(from: 0, to: section.slots.count, by: width).map { start in
                GridRow(
                    section: section.kind,
                    startsSection: start == 0,
                    slots: Array(section.slots[start..<min(start + width, section.slots.count)])
                )
            }
        }
    }

    public func move(from ssid: String?, _ direction: MoveDirection, columns: Int) -> String? {
        let rows = rows(columns: columns)
        guard let first = rows.first?.slots.first else { return nil }
        guard let ssid, let position = Self.locate(ssid, in: rows) else { return first }
        switch direction {
        case .left: return Self.step(from: position, by: -1, in: rows)
        case .right: return Self.step(from: position, by: 1, in: rows)
        case .up: return Self.hop(from: position, by: -1, in: rows)
        case .down: return Self.hop(from: position, by: 1, in: rows)
        }
    }

    private static func arrivedFirst(_ lhs: NetworkEntry, _ rhs: NetworkEntry) -> Bool {
        if lhs.firstSeen != rhs.firstSeen { return lhs.firstSeen < rhs.firstSeen }
        return LayoutEngine.ssidPrecedes(lhs.ssid, rhs.ssid)
    }

    private static func locate(_ ssid: String, in rows: [GridRow]) -> (row: Int, column: Int)? {
        for (row, content) in rows.enumerated() {
            if let column = content.slots.firstIndex(of: ssid) { return (row, column) }
        }
        return nil
    }

    private static func step(from position: (row: Int, column: Int), by delta: Int, in rows: [GridRow]) -> String {
        let column = position.column + delta
        if rows[position.row].slots.indices.contains(column) {
            return rows[position.row].slots[column]
        }
        let row = position.row + delta
        guard rows.indices.contains(row) else { return rows[position.row].slots[position.column] }
        return delta > 0 ? rows[row].slots[0] : rows[row].slots[rows[row].slots.count - 1]
    }

    private static func hop(from position: (row: Int, column: Int), by delta: Int, in rows: [GridRow]) -> String {
        let row = position.row + delta
        guard rows.indices.contains(row) else { return rows[position.row].slots[position.column] }
        return rows[row].slots[min(position.column, rows[row].slots.count - 1)]
    }
}

public enum LayoutEngine {
    public static let pruneInterval: TimeInterval = 300
    public static let dimInterval: TimeInterval = 60

    public static func freeze(_ store: inout NetworkStore, now: Date) -> FrozenLayout {
        store.prune(olderThan: pruneInterval, now: now)
        let entries = store.entries.values
        return FrozenLayout(
            known: entries.filter(\.known).sorted(by: entryPrecedes),
            other: entries.filter { !$0.known }.sorted(by: entryPrecedes)
        )
    }

    static func ssidPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        switch lhs.localizedCaseInsensitiveCompare(rhs) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
        }
    }

    private static func entryPrecedes(_ lhs: NetworkEntry, _ rhs: NetworkEntry) -> Bool {
        ssidPrecedes(lhs.ssid, rhs.ssid)
    }
}
