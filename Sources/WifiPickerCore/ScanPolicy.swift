import Foundation

public enum ScanPolicy {
    public static let cacheFreshness: TimeInterval = 120

    public static func shouldScanOnOpen(lastCacheEvent: Date?, now: Date) -> Bool {
        guard let lastCacheEvent else { return true }
        return now.timeIntervalSince(lastCacheEvent) > cacheFreshness
    }
}
