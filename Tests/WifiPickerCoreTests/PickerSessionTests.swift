import Foundation
import Testing
@testable import WifiPickerCore

@Suite struct PickerSessionTests {
    @Test func openIsRefusedUntilTheFirstCacheIngest() {
        var session = PickerSession()
        var didOpen = session.open(at: t0)
        #expect(didOpen == false)
        #expect(session.isOpen == false)

        session.ingest([sample("a"), sample("b")], at: t0)
        didOpen = session.open(at: t0)
        #expect(didOpen)
        #expect(session.layout.readingOrder == ["a", "b"])
    }

    @Test func anEmptyIngestStillCountsAsTheCacheBeingRead() {
        var session = PickerSession()
        session.ingest([], at: t0)
        let didOpen = session.open(at: t0)
        #expect(didOpen)
    }

    @Test func markingTheCacheLoadedLetsAnOpenProceedWithoutData() {
        var session = PickerSession()
        session.markCacheLoaded()
        let didOpen = session.open(at: t0)
        #expect(didOpen)
        #expect(session.layout.readingOrder.isEmpty)
    }

    @Test func aSecondOpenWhileOpenNeverRefreezes() {
        var session = PickerSession()
        session.ingest(
            [sample("016airport"), sample("Free Airport WIFI", known: true), sample("Unitedwifi.com", known: true)],
            at: t0
        )
        var didOpen = session.open(at: t0)
        #expect(didOpen)
        let frozen = session.layout.readingOrder

        session.ingest([sample("Galaxy S10", known: false), sample("Hotel", known: true)], at: t0.addingTimeInterval(3))
        let afterArrivals = session.layout.readingOrder
        #expect(Array(afterArrivals.prefix(frozen.count)) == frozen)

        didOpen = session.open(at: t0.addingTimeInterval(4))
        #expect(didOpen == false)
        #expect(session.layout.readingOrder == afterArrivals)
        #expect(session.isOpen)
    }

    @Test func closingThenOpeningRebuildsTheLayout() {
        var session = PickerSession()
        session.ingest([sample("b"), sample("a")], at: t0)
        var didOpen = session.open(at: t0)
        #expect(didOpen)
        session.ingest([sample("aa", known: true)], at: t0.addingTimeInterval(1))
        session.close()
        #expect(session.isOpen == false)

        didOpen = session.open(at: t0.addingTimeInterval(2))
        #expect(didOpen)
        #expect(session.layout.slots(in: .known) == ["aa"])
        #expect(session.layout.slots(in: .other) == ["a", "b"])
        #expect(session.layout.slots(in: .new).isEmpty)
    }

    @Test func ingestWhileClosedLeavesTheLayoutAlone() {
        var session = PickerSession()
        session.ingest([sample("a")], at: t0)
        let didOpen = session.open(at: t0)
        #expect(didOpen)
        session.close()
        let before = session.layout.sections
        session.ingest([sample("zzz")], at: t0.addingTimeInterval(5))
        #expect(session.layout.sections == before)
        #expect(session.store.entries["zzz"] != nil)
    }

    @Test func nothingReFreezesWhileOpenUnderRandomOperations() {
        for iteration in 0..<200 {
            var rng = SplitMix64(seed: UInt64(iteration) &+ 1000)
            var session = PickerSession()
            var now = t0
            var openedSlots: [String]?
            for _ in 0..<60 {
                now = now.addingTimeInterval(Double.random(in: 0...20, using: &rng))
                switch Int.random(in: 0..<4, using: &rng) {
                case 0:
                    session.ingest(randomSamples(using: &rng), at: now)
                case 1:
                    if session.open(at: now) { openedSlots = session.layout.readingOrder }
                case 2:
                    session.close()
                    openedSlots = nil
                default:
                    session.ingest([], at: now)
                }
                guard session.isOpen, let opened = openedSlots else { continue }
                #expect(
                    Array(session.layout.readingOrder.prefix(opened.count)) == opened,
                    "iteration \(iteration): slots changed while open"
                )
            }
        }
    }

    private func randomSamples(using rng: inout SplitMix64) -> [ScanSample] {
        (0..<Int.random(in: 1...8, using: &rng)).map { _ in
            sample("net-\(Int.random(in: 0..<30, using: &rng))", known: Bool.random(using: &rng))
        }
    }
}
