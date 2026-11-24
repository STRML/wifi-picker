import Foundation
import Testing
import WifiPickerCore

@Suite struct PickerSessionTests {
    // MARK: - Freeze, classification & sorting

    @Test func freezeIsIndependentOfInsertionOrder() {
        let names = ["delta", "Alpha", "charlie", "Bravo", "echo", "ALPHA", "foxtrot"]
        let known: Set<String> = ["delta", "Bravo"]
        let samples = names.map { sample($0, known: known.contains($0)) }
        let expected = openedSession(samples).columns

        var rng = SplitMix64(seed: 7)
        for _ in 0..<50 {
            let shuffled = openedSession(samples.shuffled(using: &rng))
            #expect(shuffled.columns == expected)
        }
    }

    @Test func freezeSplitsIntoHotspotsKnownAndOtherWithHotspotWinningOverKnown() {
        let session = openedSession([
            sample("zeta", known: true),
            sample("alpha"),
            sample("Sam’s iPhone", known: true),
            sample("Galaxy S10"),
        ])
        #expect(session.columns.map(\.kind) == [.hotspots, .known, .other])
        #expect(session.slots(in: .hotspots) == ["Galaxy S10", "Sam’s iPhone"])
        #expect(session.slots(in: .known) == ["zeta"])
        #expect(session.slots(in: .other) == ["alpha"])
        #expect(session.column(of: "Sam’s iPhone") == .hotspots)
        #expect(session.column(of: "zeta") == .known)
        #expect(session.column(of: "alpha") == .other)
        #expect(session.column(of: "nope") == nil)
    }

    @Test(arguments: [
        "iPhone", "Sam’s iPhone", "iPad Pro", "Galaxy S10719e", "Pixel 7", "AndroidAP_1234", "Android_6A3F",
        "OnePlus 9", "Redmi Note 11", "Xiaomi 13", "Moto G Power", "MyHotspot", "Verizon MiFi 8800L", "Jetpack 4412",
        "IPHONE", "galaxy a52", "HOTSPOT-77",
        "Sam's Phone", "Sam’s Pixel", "Alex's S23", "Maria’s Phone",
    ])
    func phoneAndHotspotNamesClassifyAsHotspots(name: String) {
        let session = openedSession([sample(name, known: true)])
        #expect(session.column(of: name) == .hotspots, "\(name)")
    }

    @Test(arguments: [
        "Free Airport WIFI", "Unitedwifi.com", "cowadlwifi12", "skyfi_secure", "@NRadio-5AB2", "016airport",
        "Remote Office", "Samotop", "Joe's Pizza", "Maria’s Cafe", "Starbucks", "NETGEAR42", "xfinitywifi", "Sam's",
        "'s home",
    ])
    func ordinaryNetworksDoNotClassifyAsHotspots(name: String) {
        let session = openedSession([sample(name, known: false)])
        #expect(session.column(of: name) == .other, "\(name)")
    }

    @Test func sortIgnoresCaseAndBreaksTiesByUTF8Bytes() throws {
        let names = ["🙂 cafe", "Cafe", "cafe", "CAFE", "☕️", "wifi", "WiFi", "Wifi", "Resume", "Résumé", "Sa"]
        let expected = openedSession(names.map { sample($0) }).slots(in: .other)
        #expect(expected.count == names.count)
        func index(_ name: String) throws -> Int { try #require(expected.firstIndex(of: name)) }
        #expect(try index("CAFE") < index("Cafe"))
        #expect(try index("Cafe") < index("cafe"))
        #expect(try index("WiFi") < index("Wifi"))
        #expect(try index("Wifi") < index("wifi"))
        #expect(try index("Resume") < index("Résumé"))

        var rng = SplitMix64(seed: 3)
        for _ in 0..<20 {
            let shuffled = openedSession(names.shuffled(using: &rng).map { sample($0) })
            #expect(shuffled.slots(in: .other) == expected)
        }
    }

    // MARK: - BSSID merging & signal mapping

    @Test func mergesBSSIDsByStrongestRSSIAndTakesSecurityFromStrongest() throws {
        let session = openedSession([
            sample("home", rssi: -70, bssid: "aa:01", secure: false, known: false),
            sample("home", rssi: -48, bssid: "aa:02", secure: true, known: false),
            sample("home", rssi: -61, bssid: "aa:03", secure: false, known: true),
            sample(""),
        ])
        #expect(session.readingOrder == ["home"])
        let cell = try #require(session.cell(for: "home", at: t0))
        #expect(cell.entry.rssi == -48)
        #expect(cell.entry.secure == true)
        #expect(cell.entry.known == true)

        let tied = openedSession([
            sample("tie", rssi: -55, bssid: "bb:02", secure: true),
            sample("tie", rssi: -55, bssid: "aa:01", secure: false),
        ])
        #expect(try #require(tied.cell(for: "tie", at: t0)).entry.secure == false)
    }

    @Test func rssiTracksLatestBatchAndSignalMapsOntoZeroToOne() throws {
        var session = openedSession([
            sample("weak", rssi: -95),
            sample("mid", rssi: -70),
            sample("strong", rssi: -30),
        ])
        #expect(try #require(session.cell(for: "weak", at: t0)).entry.signal == 0)
        #expect(try #require(session.cell(for: "strong", at: t0)).entry.signal == 1)
        let midSignal = try #require(session.cell(for: "mid", at: t0)).entry.signal
        #expect(midSignal > 0.3 && midSignal < 0.7)

        let later = t0.addingTimeInterval(15)
        session.ingest([sample("strong", rssi: -75)], at: later)
        let updated = try #require(session.cell(for: "strong", at: later))
        #expect(updated.entry.rssi == -75)
        #expect(updated.entry.firstSeen == t0)
        #expect(updated.entry.lastSeen == later)
    }

    // MARK: - Open, absorb, dimming, pruning

    @Test func secondOpenWhileOpenNeverRefreezesAndArrivalsAppendInOrder() {
        var session = openedSession([
            sample("a"),
            sample("b"),
            sample("K", known: true),
            sample("iPhone A"),
        ])
        session.ingest([sample("zz"), sample("Galaxy X")], at: t0.addingTimeInterval(1))
        session.ingest([sample("aa"), sample("Known2", known: true)], at: t0.addingTimeInterval(2))
        session.ingest([sample("Pixel 7")], at: t0.addingTimeInterval(3))

        #expect(session.slots(in: .other) == ["a", "b", "zz", "aa"])
        #expect(session.slots(in: .known) == ["K", "Known2"])
        #expect(session.slots(in: .hotspots) == ["iPhone A", "Galaxy X", "Pixel 7"])

        let before = session.columns
        let reopened = session.open(at: t0.addingTimeInterval(4))
        #expect(reopened == false)
        #expect(session.columns == before)
        #expect(session.isOpen)
    }

    @Test func knownFlipWhileOpenKeepsSlotUntilReopen() throws {
        var session = openedSession([sample("flip", known: false), sample("anchor", known: true)])
        #expect(session.slots(in: .other) == ["flip"])

        let t1 = t0.addingTimeInterval(5)
        session.ingest([sample("flip", known: true)], at: t1)
        #expect(session.slots(in: .other) == ["flip"])
        #expect(session.slots(in: .known) == ["anchor"])
        #expect(try #require(session.cell(for: "flip", at: t1)).entry.known)

        session.close()
        let reopened = session.open(at: t0.addingTimeInterval(10))
        #expect(reopened)
        #expect(session.slots(in: .known) == ["anchor", "flip"])
        #expect(session.slots(in: .other).isEmpty)
    }

    @Test func ingestWhileClosedLeavesLayoutUntouchedUntilNextOpen() {
        var session = openedSession([sample("a")])
        session.close()
        let before = session.columns
        session.ingest([sample("zzz")], at: t0.addingTimeInterval(5))
        #expect(session.columns == before)
        let reopened = session.open(at: t0.addingTimeInterval(6))
        #expect(reopened)
        #expect(session.slots(in: .other) == ["a", "zzz"])
    }

    @Test func dimsAfterSixtySecondsAndRecoversWhenSeenAgain() throws {
        var session = openedSession([sample("a"), sample("b")])
        session.ingest([sample("a")], at: t0.addingTimeInterval(59))

        #expect(try #require(session.cell(for: "b", at: t0.addingTimeInterval(59))).dimmed == false)
        #expect(try #require(session.cell(for: "b", at: t0.addingTimeInterval(60))).dimmed)
        #expect(try #require(session.cell(for: "a", at: t0.addingTimeInterval(60))).dimmed == false)
        #expect(session.cell(for: "nope", at: t0) == nil)

        let later = t0.addingTimeInterval(120)
        session.ingest([sample("b", rssi: -50)], at: later)
        let recovered = try #require(session.cell(for: "b", at: later))
        #expect(recovered.dimmed == false)
        #expect(recovered.entry.rssi == -50)
    }

    @Test func prunesEntriesUnseenOverFiveMinutesOnlyOnReopen() throws {
        var session = openedSession([sample("gone"), sample("edge"), sample("stays")])
        let later = t0.addingTimeInterval(PickerSession.pruneInterval + 1)
        session.ingest([sample("edge")], at: t0.addingTimeInterval(1))
        session.ingest([sample("stays")], at: later)

        // While still open, "gone" keeps its slot and dims.
        #expect(session.slots(in: .other) == ["edge", "gone", "stays"])
        #expect(try #require(session.cell(for: "gone", at: later)).dimmed)

        // On reopen, "gone" (> 300s) drops; "edge" (== 300s) survives.
        session.close()
        let reopened = session.open(at: later)
        #expect(reopened)
        #expect(session.slots(in: .other) == ["edge", "stays"])
        #expect(session.cell(for: "gone", at: later) == nil)
    }

    // MARK: - Grid keyboard navigation

    @Test func keyboardNavigationMovesAcrossAndWithinColumns() {
        let session = openedSession([
            sample("iPhone A"), sample("iPhone B"), sample("iPhone C"),
            sample("k1", known: true), sample("k2", known: true),
            sample("o1"),
        ])
        #expect(session.tallestColumnCount == 3)
        #expect(session.move(from: nil, .down) == "iPhone A")
        #expect(session.move(from: "ghost", .right) == "iPhone A")
        #expect(session.move(from: "iPhone A", .up) == "iPhone A")
        #expect(session.move(from: "iPhone A", .down) == "iPhone B")
        #expect(session.move(from: "iPhone C", .down) == "iPhone C")
        #expect(session.move(from: "iPhone C", .right) == "k2")
        #expect(session.move(from: "k2", .right) == "o1")
        #expect(session.move(from: "o1", .right) == "o1")
        #expect(session.move(from: "o1", .left) == "k1")
        #expect(session.move(from: "iPhone A", .left) == "iPhone A")

        let skipped = openedSession([sample("iPhone A"), sample("o1"), sample("o2")])
        #expect(skipped.move(from: "iPhone A", .right) == "o1")
        #expect(skipped.move(from: "o2", .left) == "iPhone A")

        let empty = openedSession([])
        #expect(empty.tallestColumnCount == 0)
        #expect(empty.move(from: nil, .down) == nil)
    }
}
