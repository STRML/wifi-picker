import Foundation
import Testing
@testable import WifiPickerCore

@Suite struct LayoutEngineTests {
    @Test func freezeIsIndependentOfInsertionOrder() {
        let names = ["delta", "Alpha", "charlie", "Bravo", "echo", "ALPHA", "foxtrot"]
        let known: Set<String> = ["delta", "Bravo"]
        let samples = names.map { sample($0, known: known.contains($0)) }

        var baseline = store(samples)
        let expected = LayoutEngine.freeze(&baseline, now: t0)

        var rng = SplitMix64(seed: 7)
        for _ in 0..<50 {
            var shuffled = store(samples.shuffled(using: &rng))
            let layout = LayoutEngine.freeze(&shuffled, now: t0)
            #expect(layout.columns == expected.columns)
        }
    }

    @Test func freezeSplitsIntoHotspotsKnownAndOther() {
        var s = store([
            sample("zeta", known: true),
            sample("alpha"),
            sample("Sam’s iPhone", known: true),
            sample("Galaxy S10"),
        ])
        let layout = LayoutEngine.freeze(&s, now: t0)
        #expect(layout.columns.map(\.kind) == [.hotspots, .known, .other])
        #expect(layout.slots(in: .hotspots) == ["Galaxy S10", "Sam’s iPhone"])
        #expect(layout.slots(in: .known) == ["zeta"])
        #expect(layout.slots(in: .other) == ["alpha"])
    }

    @Test func sortIgnoresCaseAndBreaksTiesByBytes() {
        var s = store(["b", "A", "a", "B", "Resume", "Résumé", "Sa"].map { sample($0) })
        let layout = LayoutEngine.freeze(&s, now: t0)
        #expect(layout.slots(in: .other) == ["A", "a", "B", "b", "Resume", "Résumé", "Sa"])
    }

    @Test func sortIsStableForEmojiAndIdenticalIgnoringCase() throws {
        let names = ["🙂 cafe", "Cafe", "cafe", "CAFE", "☕️", "wifi", "WiFi", "Wifi"]
        var rng = SplitMix64(seed: 3)
        var reference = store(names.map { sample($0) })
        let expected = LayoutEngine.freeze(&reference, now: t0).slots(in: .other)
        #expect(expected.count == names.count)
        func index(_ name: String) throws -> Int { try #require(expected.firstIndex(of: name)) }
        #expect(try index("CAFE") < index("Cafe"))
        #expect(try index("Cafe") < index("cafe"))
        #expect(try index("WiFi") < index("Wifi"))
        #expect(try index("Wifi") < index("wifi"))
        for _ in 0..<20 {
            var shuffled = store(names.shuffled(using: &rng).map { sample($0) })
            #expect(LayoutEngine.freeze(&shuffled, now: t0).slots(in: .other) == expected)
        }
    }

    @Test func prunedEntryDropsAtNextFreezeButKeepsItsSlotInTheOldLayout() throws {
        var s = store([sample("gone"), sample("stays")])
        var open = LayoutEngine.freeze(&s, now: t0)
        let later = t0.addingTimeInterval(LayoutEngine.pruneInterval + 100)

        s.ingest([sample("stays")], at: later)
        open.absorb(s)
        #expect(open.slots(in: .other) == ["gone", "stays"])
        let cell = try #require(open.cell(for: "gone", in: s, now: later))
        #expect(cell.dimmed)

        let next = LayoutEngine.freeze(&s, now: later)
        #expect(next.slots(in: .other) == ["stays"])
        #expect(s.entries["gone"] == nil)
        #expect(open.slots(in: .other) == ["gone", "stays"])
        #expect(open.cell(for: "gone", in: s, now: later)?.dimmed == true)
    }

    @Test func entryUnseenForExactlyPruneIntervalSurvivesFreeze() {
        var s = store([sample("edge")])
        let layout = LayoutEngine.freeze(&s, now: t0.addingTimeInterval(LayoutEngine.pruneInterval))
        #expect(layout.slots(in: .other) == ["edge"])
    }

    @Test func knownFlipWhileOpenKeepsTheOtherSlot() {
        var s = store([sample("flip", known: false), sample("anchor", known: true)])
        var layout = LayoutEngine.freeze(&s, now: t0)
        #expect(layout.slots(in: .other) == ["flip"])

        s.ingest([sample("flip", known: true)], at: t0.addingTimeInterval(5))
        layout.absorb(s)
        #expect(layout.slots(in: .other) == ["flip"])
        #expect(layout.slots(in: .known) == ["anchor"])
        #expect(layout.cell(for: "flip", in: s, now: t0.addingTimeInterval(5))?.entry.known == true)

        var reopened = s
        let next = LayoutEngine.freeze(&reopened, now: t0.addingTimeInterval(10))
        #expect(next.slots(in: .known) == ["anchor", "flip"])
    }

    @Test func newSSIDsAppendToTheBottomOfTheirOwnColumnInArrivalOrder() {
        var s = store([sample("a"), sample("b"), sample("K", known: true), sample("iPhone A")])
        var layout = LayoutEngine.freeze(&s, now: t0)

        s.ingest([sample("zz"), sample("Galaxy X")], at: t0.addingTimeInterval(1))
        s.ingest([sample("aa"), sample("Known2", known: true)], at: t0.addingTimeInterval(2))
        s.ingest([sample("Pixel 7")], at: t0.addingTimeInterval(3))
        layout.absorb(s)
        #expect(layout.slots(in: .other) == ["a", "b", "zz", "aa"])
        #expect(layout.slots(in: .known) == ["K", "Known2"])
        #expect(layout.slots(in: .hotspots) == ["iPhone A", "Galaxy X", "Pixel 7"])
    }

    @Test func aHotspotThatIsAlsoKnownGoesToHotspots() {
        var s = store([sample("Sam’s iPhone", known: true)])
        let layout = LayoutEngine.freeze(&s, now: t0)
        #expect(layout.slots(in: .hotspots) == ["Sam’s iPhone"])
        #expect(layout.slots(in: .known).isEmpty)
    }

    @Test func columnOfReportsMembership() {
        var s = store([sample("iPhone"), sample("home", known: true), sample("cafe")])
        let layout = LayoutEngine.freeze(&s, now: t0)
        #expect(layout.column(of: "iPhone") == .hotspots)
        #expect(layout.column(of: "home") == .known)
        #expect(layout.column(of: "cafe") == .other)
        #expect(layout.column(of: "nope") == nil)
    }

    @Test func absorbIsIdempotent() {
        var s = store([sample("a")])
        var layout = LayoutEngine.freeze(&s, now: t0)
        s.ingest([sample("n")], at: t0.addingTimeInterval(1))
        layout.absorb(s)
        let once = layout.columns
        layout.absorb(s)
        #expect(layout.columns == once)
    }
}
