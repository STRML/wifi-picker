import Foundation
import Testing
import WifiPickerCore

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
                    secure: Bool.random(using: &rng),
                    known: Bool.random(using: &rng)
                )
            }
        }
    }

    private static func membership(_ session: PickerSession) -> [String: ColumnKind] {
        var result: [String: ColumnKind] = [:]
        for column in session.columns {
            for ssid in column.slots { result[ssid] = column.kind }
        }
        return result
    }

    @Test func columnsOnlyAppendAfterFreeze() {
        for iteration in 0..<500 {
            var rng = SplitMix64(seed: UInt64(iteration) &+ 1)
            var session = PickerSession()
            var now = t0
            var seenSSIDs: Set<String> = []

            let initial = Self.randomBatch(using: &rng)
            seenSSIDs.formUnion(initial.map(\.ssid))
            session.ingest(initial, at: now)
            let opened = session.open(at: now)
            #expect(opened)

            for _ in 0..<Int.random(in: 1...30, using: &rng) {
                let before = ColumnKind.allCases.map { session.slots(in: $0) }
                let placed = Self.membership(session)
                now = now.addingTimeInterval(Double.random(in: 0...90, using: &rng))
                let batch = Self.randomBatch(using: &rng)
                seenSSIDs.formUnion(batch.map(\.ssid))
                session.ingest(batch, at: now)

                for (index, kind) in ColumnKind.allCases.enumerated() {
                    let after = session.slots(in: kind)
                    #expect(
                        Array(after.prefix(before[index].count)) == before[index],
                        "iteration \(iteration): \(kind) slots changed"
                    )
                }
                let afterMembership = Self.membership(session)
                for (ssid, kind) in placed {
                    #expect(afterMembership[ssid] == kind, "iteration \(iteration): \(ssid) changed column")
                }
                #expect(Set(session.readingOrder).count == session.readingOrder.count, "iteration \(iteration)")
            }
            #expect(!session.readingOrder.isEmpty, "iteration \(iteration)")
            #expect(Set(session.readingOrder) == seenSSIDs, "iteration \(iteration)")
        }
    }

    @Test func everyIngestedSSIDEndsUpInASlotWhenOpenedEmpty() {
        var rng = SplitMix64(seed: 99)
        var session = PickerSession()
        var seenSSIDs: Set<String> = []
        let opened = session.open(at: t0)
        #expect(opened)
        for step in 0..<20 {
            let batch = Self.randomBatch(using: &rng)
            seenSSIDs.formUnion(batch.map(\.ssid))
            session.ingest(batch, at: t0.addingTimeInterval(Double(step)))
        }
        #expect(!seenSSIDs.isEmpty)
        #expect(Set(session.readingOrder) == seenSSIDs)
    }

    @Test func nothingReFreezesWhileOpenUnderRandomOperations() {
        for iteration in 0..<200 {
            var rng = SplitMix64(seed: UInt64(iteration) &+ 1000)
            var session = PickerSession()
            var now = t0
            var openedColumns: [LayoutColumn]?
            for _ in 0..<60 {
                now = now.addingTimeInterval(Double.random(in: 0...20, using: &rng))
                switch Int.random(in: 0..<4, using: &rng) {
                case 0:
                    let batch = (0..<Int.random(in: 1...8, using: &rng)).map { _ in
                        sample("net-\(Int.random(in: 0..<30, using: &rng))", known: Bool.random(using: &rng))
                    }
                    session.ingest(batch, at: now)
                case 1:
                    if session.open(at: now) { openedColumns = session.columns }
                case 2:
                    session.close()
                    openedColumns = nil
                default:
                    session.ingest([], at: now)
                }
                guard session.isOpen, let opened = openedColumns else { continue }
                let grewOnly = zip(opened, session.columns).allSatisfy {
                    Array($1.slots.prefix($0.slots.count)) == $0.slots
                }
                #expect(grewOnly, "iteration \(iteration): slots changed while open")
            }
        }
    }
}
