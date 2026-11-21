import Foundation
import Testing
@testable import WifiPickerCore

@Suite struct NetworkStoreTests {
    @Test func threeBSSIDsOfOneSSIDMergeIntoOneEntryWithTheStrongest() throws {
        let s = store([
            sample("home", rssi: -70, bssid: "aa:01", band: .ghz2, secure: true),
            sample("home", rssi: -48, bssid: "aa:02", band: .ghz5, secure: true),
            sample("home", rssi: -61, bssid: "aa:03", band: .ghz6, secure: true),
        ])
        #expect(s.entries.count == 1)
        let entry = try #require(s.entries["home"])
        #expect(entry.rssi == -48)
        #expect(entry.band == .ghz5)
    }

    @Test func securityComesFromTheStrongestBSSID() throws {
        let s = store([
            sample("mixed", rssi: -80, bssid: "aa:01", secure: false),
            sample("mixed", rssi: -45, bssid: "aa:02", secure: true),
        ])
        #expect(try #require(s.entries["mixed"]).secure)

        let flipped = store([
            sample("mixed", rssi: -45, bssid: "aa:01", secure: false),
            sample("mixed", rssi: -80, bssid: "aa:02", secure: true),
        ])
        #expect(try #require(flipped.entries["mixed"]).secure == false)
    }

    @Test func rssiTracksTheLatestBatchNotTheHistoricalMaximum() throws {
        var s = store([sample("home", rssi: -40)])
        s.ingest([sample("home", rssi: -75)], at: t0.addingTimeInterval(10))
        #expect(try #require(s.entries["home"]).rssi == -75)
    }

    @Test func firstSeenSticksAndLastSeenAdvances() throws {
        var s = store([sample("home")])
        s.ingest([sample("home")], at: t0.addingTimeInterval(42))
        let entry = try #require(s.entries["home"])
        #expect(entry.firstSeen == t0)
        #expect(entry.lastSeen == t0.addingTimeInterval(42))
    }

    @Test func aBatchNeverRemovesEntries() {
        var s = store([sample("a"), sample("b")])
        s.ingest([sample("a")], at: t0.addingTimeInterval(5))
        s.ingest([], at: t0.addingTimeInterval(10))
        #expect(Set(s.entries.keys) == ["a", "b"])
    }

    @Test func missingFromOneBatchKeepsItsLastSeen() throws {
        var s = store([sample("a"), sample("b")])
        s.ingest([sample("a")], at: t0.addingTimeInterval(30))
        #expect(try #require(s.entries["b"]).lastSeen == t0)
    }

    @Test func emptySSIDsAreIgnored() {
        let s = store([sample(""), sample("real")])
        #expect(Set(s.entries.keys) == ["real"])
    }

    @Test func knownIsTrueWhenAnyBSSIDIsKnown() throws {
        let s = store([
            sample("home", rssi: -40, bssid: "aa:01", known: false),
            sample("home", rssi: -60, bssid: "aa:02", known: true),
        ])
        #expect(try #require(s.entries["home"]).known)
    }

    @Test func signalMapsRSSIOntoZeroToOne() throws {
        let weak = try #require(store([sample("w", rssi: -95)]).entries["w"])
        let strong = try #require(store([sample("s", rssi: -30)]).entries["s"])
        let mid = try #require(store([sample("m", rssi: -70)]).entries["m"])
        #expect(weak.signal == 0)
        #expect(strong.signal == 1)
        #expect(mid.signal > 0.3 && mid.signal < 0.7)
    }

    @Test func pruneDropsOnlyEntriesOlderThanTheInterval() {
        var s = store([sample("old")])
        s.ingest([sample("fresh")], at: t0.addingTimeInterval(200))
        s.prune(olderThan: 100, now: t0.addingTimeInterval(201))
        #expect(Set(s.entries.keys) == ["fresh"])
    }
}
