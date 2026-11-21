import Foundation
import Testing
@testable import WifiPickerCore

@Suite struct GridNavigationTests {
    private func layout(hotspots: [String] = [], known: [String] = [], other: [String] = []) -> FrozenLayout {
        var s = store(
            hotspots.map { sample($0) } + known.map { sample($0, known: true) } + other.map { sample($0) }
        )
        return LayoutEngine.freeze(&s, now: t0)
    }

    private let hotspots = ["iPhone A", "iPhone B", "iPhone C"]

    @Test func upAndDownStayInsideTheColumnAndClampAtTheEnds() {
        let l = layout(hotspots: hotspots, known: ["k1", "k2"])
        #expect(l.move(from: "iPhone A", .down) == "iPhone B")
        #expect(l.move(from: "iPhone C", .down) == "iPhone C")
        #expect(l.move(from: "iPhone B", .up) == "iPhone A")
        #expect(l.move(from: "iPhone A", .up) == "iPhone A")
        #expect(l.move(from: "k2", .down) == "k2")
    }

    @Test func leftAndRightKeepTheRowIndexAndClampToTheShorterColumn() {
        let l = layout(hotspots: hotspots, known: ["k1", "k2"], other: ["o1"])
        #expect(l.move(from: "iPhone B", .right) == "k2")
        #expect(l.move(from: "iPhone C", .right) == "k2")
        #expect(l.move(from: "k2", .right) == "o1")
        #expect(l.move(from: "o1", .left) == "k1")
        #expect(l.move(from: "k2", .left) == "iPhone B")
    }

    @Test func leftAndRightStopAtTheOuterColumns() {
        let l = layout(hotspots: ["iPhone A"], known: ["k1"], other: ["o1"])
        #expect(l.move(from: "iPhone A", .left) == "iPhone A")
        #expect(l.move(from: "o1", .right) == "o1")
    }

    @Test func leftAndRightSkipEmptyColumns() {
        let l = layout(hotspots: ["iPhone A"], other: ["o1", "o2"])
        #expect(l.move(from: "iPhone A", .right) == "o1")
        #expect(l.move(from: "o2", .left) == "iPhone A")
    }

    @Test func movingFromNothingLandsOnTheFirstSlotOfTheFirstFilledColumn() {
        let l = layout(known: ["k1", "k2"], other: ["o1"])
        #expect(l.move(from: nil, .down) == "k1")
        #expect(l.move(from: nil, .left) == "k1")
    }

    @Test func movingFromAnUnknownSSIDLandsOnTheFirstSlot() {
        let l = layout(other: ["x", "y"])
        #expect(l.move(from: "ghost", .right) == "x")
    }

    @Test func movingInAnEmptyLayoutReturnsNothing() {
        var s = NetworkStore()
        let l = LayoutEngine.freeze(&s, now: t0)
        #expect(l.move(from: nil, .down) == nil)
    }

    @Test func tallestColumnCountDrivesTheHeight() {
        let l = layout(hotspots: ["iPhone A"], known: ["k1", "k2", "k3"], other: ["o1", "o2"])
        #expect(l.tallestColumnCount == 3)
        var s = NetworkStore()
        #expect(LayoutEngine.freeze(&s, now: t0).tallestColumnCount == 0)
    }
}
