import Foundation
import Testing
@testable import WifiPickerCore

@Suite struct GridNavigationTests {
    private func layout(known: [String], other: [String]) -> FrozenLayout {
        var s = store(known.map { sample($0, known: true) } + other.map { sample($0) })
        return LayoutEngine.freeze(&s, now: t0)
    }

    @Test func rowsFillRowByRowAndEachSectionStartsANewRow() {
        let l = layout(known: ["a", "b", "c", "d"], other: ["e", "f"])
        let rows = l.rows(columns: 3)
        #expect(rows.map(\.slots) == [["a", "b", "c"], ["d"], ["e", "f"]])
        #expect(rows.map(\.section) == [.known, .known, .other])
        #expect(rows.map(\.startsSection) == [true, false, true])
    }

    @Test func emptySectionsProduceNoRows() {
        let l = layout(known: [], other: ["a"])
        #expect(l.rows(columns: 3).map(\.slots) == [["a"]])
    }

    @Test func rightAndLeftWalkReadingOrderAcrossRows() {
        let l = layout(known: ["a", "b", "c", "d"], other: ["e"])
        #expect(l.move(from: "c", .right, columns: 3) == "d")
        #expect(l.move(from: "d", .right, columns: 3) == "e")
        #expect(l.move(from: "e", .right, columns: 3) == "e")
        #expect(l.move(from: "d", .left, columns: 3) == "c")
        #expect(l.move(from: "a", .left, columns: 3) == "a")
    }

    @Test func downAndUpKeepTheColumnAndClampToShortRows() {
        let l = layout(known: ["a", "b", "c", "d"], other: ["e", "f"])
        #expect(l.move(from: "a", .down, columns: 3) == "d")
        #expect(l.move(from: "c", .down, columns: 3) == "d")
        #expect(l.move(from: "d", .down, columns: 3) == "e")
        #expect(l.move(from: "f", .up, columns: 3) == "d")
        #expect(l.move(from: "e", .up, columns: 3) == "d")
        #expect(l.move(from: "a", .up, columns: 3) == "a")
        #expect(l.move(from: "f", .down, columns: 3) == "f")
    }

    @Test func movingFromNothingLandsOnTheFirstSlot() {
        let l = layout(known: [], other: ["x", "y"])
        #expect(l.move(from: nil, .down, columns: 3) == "x")
        #expect(l.move(from: nil, .left, columns: 3) == "x")
    }

    @Test func movingInAnEmptyLayoutReturnsNothing() {
        var s = NetworkStore()
        let l = LayoutEngine.freeze(&s, now: t0)
        #expect(l.move(from: nil, .down, columns: 3) == nil)
    }

    @Test func movingFromAnUnknownSSIDLandsOnTheFirstSlot() {
        let l = layout(known: [], other: ["x", "y"])
        #expect(l.move(from: "ghost", .right, columns: 3) == "x")
    }
}
