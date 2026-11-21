import Foundation

public struct NetworkEntry: Sendable, Equatable {
    public var ssid: String
    public var rssi: Int
    public var band: Band
    public var secure: Bool
    public var known: Bool
    public var firstSeen: Date
    public var lastSeen: Date

    public var signal: Double {
        let weakest = -90.0
        let strongest = -45.0
        return min(1, max(0, (Double(rssi) - weakest) / (strongest - weakest)))
    }
}

public struct NetworkStore: Sendable {
    public private(set) var entries: [String: NetworkEntry] = [:]

    public init() {}

    public mutating func ingest(_ samples: [ScanSample], at now: Date) {
        let groups = Dictionary(grouping: samples.filter { !$0.ssid.isEmpty }, by: \.ssid)
        for (ssid, group) in groups {
            guard let strongest = group.min(by: Self.strongerFirst) else { continue }
            entries[ssid] = NetworkEntry(
                ssid: ssid,
                rssi: strongest.rssi,
                band: strongest.band,
                secure: strongest.secure,
                known: group.contains { $0.known },
                firstSeen: entries[ssid]?.firstSeen ?? now,
                lastSeen: now
            )
        }
    }

    mutating func prune(olderThan interval: TimeInterval, now: Date) {
        entries = entries.filter { now.timeIntervalSince($0.value.lastSeen) <= interval }
    }

    private static func strongerFirst(_ lhs: ScanSample, _ rhs: ScanSample) -> Bool {
        if lhs.rssi != rhs.rssi { return lhs.rssi > rhs.rssi }
        return lhs.bssid < rhs.bssid
    }
}
