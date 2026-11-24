import Foundation

struct NetworkStore: Sendable {
    private(set) var entries: [String: NetworkEntry] = [:]

    mutating func ingest(_ samples: [ScanSample], at now: Date) {
        let groups = Dictionary(grouping: samples.filter { !$0.ssid.isEmpty }, by: \.ssid)
        for (ssid, group) in groups {
            guard let strongest = group.min(by: Self.strongerFirst) else { continue }
            entries[ssid] = NetworkEntry(
                ssid: ssid,
                rssi: strongest.rssi,
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

    static func strongerFirst(_ lhs: ScanSample, _ rhs: ScanSample) -> Bool {
        if lhs.rssi != rhs.rssi { return lhs.rssi > rhs.rssi }
        return lhs.bssid < rhs.bssid
    }
}
