import Foundation
import Testing
@testable import WifiPickerCore

@Suite struct DimmingTests {
    @Test func missingFromOneBatchIsNotDimmed() throws {
        var s = store([sample("a"), sample("b")])
        let layout = LayoutEngine.freeze(&s, now: t0)
        let now = t0.addingTimeInterval(30)
        s.ingest([sample("a")], at: now)

        let cell = try #require(layout.cell(for: "b", in: s, now: now))
        #expect(cell.dimmed == false)
    }

    @Test func dimsOnlyOnceSixtySecondsHavePassed() throws {
        var s = store([sample("a"), sample("b")])
        let layout = LayoutEngine.freeze(&s, now: t0)
        s.ingest([sample("a")], at: t0.addingTimeInterval(59))

        #expect(try #require(layout.cell(for: "b", in: s, now: t0.addingTimeInterval(59))).dimmed == false)
        #expect(try #require(layout.cell(for: "b", in: s, now: t0.addingTimeInterval(60))).dimmed)
        #expect(try #require(layout.cell(for: "a", in: s, now: t0.addingTimeInterval(60))).dimmed == false)
    }

    @Test func aDimmedEntryRecoversWhenItReturns() throws {
        var s = store([sample("a")])
        let layout = LayoutEngine.freeze(&s, now: t0)
        let later = t0.addingTimeInterval(120)
        #expect(try #require(layout.cell(for: "a", in: s, now: later)).dimmed)

        s.ingest([sample("a", rssi: -50)], at: later)
        let cell = try #require(layout.cell(for: "a", in: s, now: later))
        #expect(cell.dimmed == false)
        #expect(cell.entry.rssi == -50)
    }

    @Test func unknownSSIDHasNoCell() {
        var s = store([sample("a")])
        let layout = LayoutEngine.freeze(&s, now: t0)
        #expect(layout.cell(for: "nope", in: s, now: t0) == nil)
    }
}
