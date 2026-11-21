import Foundation
import Testing
@testable import WifiPickerCore

@Suite struct ScanPolicyTests {
    @Test func scansWhenNoCacheEventHasBeenSeen() {
        #expect(ScanPolicy.shouldScanOnOpen(lastCacheEvent: nil, now: t0))
    }

    @Test func skipsTheScanWhenMacOSRefreshedTheCacheRecently() {
        let event = t0.addingTimeInterval(-30)
        #expect(ScanPolicy.shouldScanOnOpen(lastCacheEvent: event, now: t0) == false)
    }

    @Test func scansOnceTheLastCacheEventIsOlderThanTwoMinutes() {
        #expect(ScanPolicy.shouldScanOnOpen(lastCacheEvent: t0.addingTimeInterval(-120), now: t0) == false)
        #expect(ScanPolicy.shouldScanOnOpen(lastCacheEvent: t0.addingTimeInterval(-121), now: t0))
    }

    @Test func aClockThatWentBackwardsCountsAsFresh() {
        #expect(ScanPolicy.shouldScanOnOpen(lastCacheEvent: t0.addingTimeInterval(500), now: t0) == false)
    }
}
