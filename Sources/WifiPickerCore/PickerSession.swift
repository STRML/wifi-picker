import Foundation

public struct PickerSession: Sendable {
    public private(set) var store = NetworkStore()
    public private(set) var layout: FrozenLayout
    public private(set) var isOpen = false
    public private(set) var cacheLoaded = false

    public init() {
        var empty = NetworkStore()
        layout = LayoutEngine.freeze(&empty, now: Date(timeIntervalSince1970: 0))
    }

    public mutating func ingest(_ samples: [ScanSample], at now: Date) {
        cacheLoaded = true
        store.ingest(samples, at: now)
        guard isOpen else { return }
        layout.absorb(store)
    }

    public mutating func markCacheLoaded() {
        cacheLoaded = true
    }

    @discardableResult
    public mutating func open(at now: Date) -> Bool {
        guard !isOpen, cacheLoaded else { return false }
        layout = LayoutEngine.freeze(&store, now: now)
        isOpen = true
        return true
    }

    public mutating func close() {
        isOpen = false
    }
}
