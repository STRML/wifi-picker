import Foundation

public enum PickerEnvironmentEvent: Sendable, Equatable {
    case samples([ScanSample])
    case cacheUpdated
    case interface(InterfaceState)
    case powerChanged(InterfaceState)
    case locationAccess(LocationAccess)
    case scanStarted
    case scanFinished(failed: Bool)
    case joinFinished(ssid: String, outcome: JoinOutcome)
    case stats(LinkStats?)
}

public protocol PickerEnvironment: AnyObject, Sendable {
    var events: AsyncStream<PickerEnvironmentEvent> { get }
    var initialLocationAccess: LocationAccess { get }

    func start()
    func cachedSamples() async -> [ScanSample]
    @MainActor func requestLocationIfNeeded()
    func refreshCache()
    func scan()
    func setPower(_ on: Bool)
    func join(ssid: String, password: String?, secure: Bool)
    func setLive(_ on: Bool)
}

public struct PickerClock: Sendable {
    public var now: @Sendable () -> Date
    public var sleep: @Sendable (Duration) async throws -> Void

    public init(
        now: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.now = now
        self.sleep = sleep
    }

    public static let live = PickerClock(
        now: { Date() },
        sleep: { try await Task.sleep(for: $0) }
    )
}
