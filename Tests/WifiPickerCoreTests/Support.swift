import Foundation
import WifiPickerCore

let t0 = Date(timeIntervalSince1970: 1_800_000_000)

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func sample(
    _ ssid: String,
    rssi: Int = -60,
    bssid: String? = nil,
    secure: Bool = true,
    known: Bool = false
) -> ScanSample {
    ScanSample(
        ssid: ssid,
        bssid: bssid ?? "00:00:00:00:00:\(ssid.utf8.count)",
        rssi: rssi,
        secure: secure,
        known: known
    )
}

func openedSession(_ samples: [ScanSample], at time: Date = t0) -> PickerSession {
    var session = PickerSession()
    session.ingest(samples, at: time)
    session.open(at: time)
    return session
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private var sleepers: [CheckedContinuation<Void, any Error>] = []

    init(start: Date = t0) {
        current = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func set(_ date: Date) {
        lock.lock()
        current = date
        lock.unlock()
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(interval)
        let pending = sleepers
        sleepers.removeAll()
        lock.unlock()
        for sleeper in pending {
            sleeper.resume()
        }
    }

    func makeClock() -> PickerClock {
        PickerClock(
            now: { self.now },
            sleep: { _ in
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        self.lock.lock()
                        if Task.isCancelled {
                            self.lock.unlock()
                            continuation.resume(throwing: CancellationError())
                        } else {
                            self.sleepers.append(continuation)
                            self.lock.unlock()
                        }
                    }
                } onCancel: {
                    self.cancelAllSleepers()
                }
            }
        )
    }

    private func cancelAllSleepers() {
        lock.lock()
        let pending = sleepers
        sleepers.removeAll()
        lock.unlock()
        for sleeper in pending {
            sleeper.resume(throwing: CancellationError())
        }
    }
}

final class FakeEnvironment: PickerEnvironment, @unchecked Sendable {
    struct JoinCall: Equatable {
        let ssid: String
        let password: String?
        let secure: Bool
    }

    let events: AsyncStream<PickerEnvironmentEvent>
    let initialLocationAccess: LocationAccess

    private let continuation: AsyncStream<PickerEnvironmentEvent>.Continuation
    private let lock = NSLock()

    private var _cachedSamples: [ScanSample] = []
    private var _suspendCacheRead = false
    private var _pendingCacheReads: [CheckedContinuation<[ScanSample], Never>] = []
    private var _startCount = 0
    private var _locationRequests = 0
    private var _refreshCacheCount = 0
    private var _scanCount = 0
    private var _powerChanges: [Bool] = []
    private var _joins: [JoinCall] = []
    private var _liveChanges: [Bool] = []

    init(initialLocationAccess: LocationAccess = .granted, cachedSamples: [ScanSample] = []) {
        let pair = AsyncStream.makeStream(of: PickerEnvironmentEvent.self, bufferingPolicy: .unbounded)
        events = pair.stream
        continuation = pair.continuation
        self.initialLocationAccess = initialLocationAccess
        self._cachedSamples = cachedSamples
    }

    var cachedSamplesResult: [ScanSample] {
        get { withLock { _cachedSamples } }
        set { withLock { _cachedSamples = newValue } }
    }

    var suspendCacheRead: Bool {
        get { withLock { _suspendCacheRead } }
        set { withLock { _suspendCacheRead = newValue } }
    }

    var pendingCacheReadCount: Int { withLock { _pendingCacheReads.count } }
    var startCount: Int { withLock { _startCount } }
    var locationRequests: Int { withLock { _locationRequests } }
    var refreshCacheCount: Int { withLock { _refreshCacheCount } }
    var scanCount: Int { withLock { _scanCount } }
    var powerChanges: [Bool] { withLock { _powerChanges } }
    var joins: [JoinCall] { withLock { _joins } }
    var liveChanges: [Bool] { withLock { _liveChanges } }

    func start() {
        withLock { _startCount += 1 }
    }

    func cachedSamples() async -> [ScanSample] {
        let shouldSuspend = withLock { _suspendCacheRead }
        if !shouldSuspend {
            return withLock { _cachedSamples }
        }
        return await withCheckedContinuation { continuation in
            withLock { _pendingCacheReads.append(continuation) }
        }
    }

    func resumeNextCacheRead(with samples: [ScanSample]? = nil) {
        let next: (CheckedContinuation<[ScanSample], Never>, [ScanSample])? = withLock {
            guard !_pendingCacheReads.isEmpty else { return nil }
            let continuation = _pendingCacheReads.removeFirst()
            return (continuation, samples ?? _cachedSamples)
        }
        next?.0.resume(returning: next?.1 ?? [])
    }

    @MainActor
    func requestLocationIfNeeded() {
        withLock { _locationRequests += 1 }
    }

    func refreshCache() {
        withLock { _refreshCacheCount += 1 }
    }

    func scan() {
        withLock { _scanCount += 1 }
    }

    func setPower(_ on: Bool) {
        withLock { _powerChanges.append(on) }
    }

    func join(ssid: String, password: String?, secure: Bool) {
        withLock { _joins.append(JoinCall(ssid: ssid, password: password, secure: secure)) }
    }

    func setLive(_ on: Bool) {
        withLock { _liveChanges.append(on) }
    }

    func send(_ event: PickerEnvironmentEvent) {
        continuation.yield(event)
    }

    func finish() {
        continuation.finish()
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

@MainActor
func drainMainActor(ticks: Int = 10) async {
    for _ in 0..<ticks {
        await Task.yield()
    }
}
