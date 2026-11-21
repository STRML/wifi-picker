import Foundation
import Testing
@testable import WifiPickerCore

@Suite struct FrozenLayoutPropertyTests {
    private static let pool = (0..<60).map { $0 % 6 == 0 ? "Galaxy-\($0)" : "net-\($0)" }

    private static func randomBatch(using rng: inout SplitMix64) -> [ScanSample] {
        let count = Int.random(in: 1...25, using: &rng)
        return (0..<count).flatMap { _ -> [ScanSample] in
            let ssid = pool.randomElement(using: &rng)!
            let bssids = Int.random(in: 1...3, using: &rng)
            return (0..<bssids).map { index in
                ScanSample(
                    ssid: ssid,
                    bssid: "\(ssid)-\(index)",
                    rssi: Int.random(in: -95 ... -30, using: &rng),
                    band: [Band.ghz2, .ghz5, .ghz6].randomElement(using: &rng)!,
                    secure: Bool.random(using: &rng),
                    known: Bool.random(using: &rng)
                )
            }
        }
    }

    private static func membership(_ layout: FrozenLayout) -> [String: ColumnKind] {
        var result: [String: ColumnKind] = [:]
        for column in layout.columns {
            for ssid in column.slots { result[ssid] = column.kind }
        }
        return result
    }

    @Test func columnsOnlyAppendAfterFreeze() {
        for iteration in 0..<500 {
            var rng = SplitMix64(seed: UInt64(iteration) &+ 1)
            var store = NetworkStore()
            var now = t0
            store.ingest(Self.randomBatch(using: &rng), at: now)
            var layout = LayoutEngine.freeze(&store, now: now)

            for _ in 0..<Int.random(in: 1...30, using: &rng) {
                let before = ColumnKind.allCases.map { layout.slots(in: $0) }
                let placed = Self.membership(layout)
                now = now.addingTimeInterval(Double.random(in: 0...90, using: &rng))
                store.ingest(Self.randomBatch(using: &rng), at: now)
                layout.absorb(store)

                for (index, kind) in ColumnKind.allCases.enumerated() {
                    let after = layout.slots(in: kind)
                    #expect(
                        Array(after.prefix(before[index].count)) == before[index],
                        "iteration \(iteration): \(kind) slots changed"
                    )
                }
                let afterMembership = Self.membership(layout)
                for (ssid, kind) in placed {
                    #expect(afterMembership[ssid] == kind, "iteration \(iteration): \(ssid) changed column")
                }
                #expect(Set(layout.readingOrder).count == layout.readingOrder.count, "iteration \(iteration)")
            }
            #expect(!layout.readingOrder.isEmpty, "iteration \(iteration)")
            #expect(Set(layout.readingOrder) == Set(store.entries.keys), "iteration \(iteration)")
        }
    }

    @Test func everyIngestedSSIDEndsUpInASlot() {
        var rng = SplitMix64(seed: 99)
        var store = NetworkStore()
        var layout = LayoutEngine.freeze(&store, now: t0)
        for step in 0..<20 {
            store.ingest(Self.randomBatch(using: &rng), at: t0.addingTimeInterval(Double(step)))
            layout.absorb(store)
        }
        #expect(!store.entries.isEmpty)
        #expect(Set(layout.readingOrder) == Set(store.entries.keys))
    }
}
