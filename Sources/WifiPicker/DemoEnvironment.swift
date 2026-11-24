import Foundation
import WifiPickerCore

final class DemoEnvironment: PickerEnvironment, @unchecked Sendable {
    let events: AsyncStream<PickerEnvironmentEvent>
    let initialLocationAccess: LocationAccess = .granted

    private let continuation: AsyncStream<PickerEnvironmentEvent>.Continuation

    init() {
        let pair = AsyncStream.makeStream(of: PickerEnvironmentEvent.self, bufferingPolicy: .unbounded)
        events = pair.stream
        continuation = pair.continuation
    }

    func start() {
        emitDemo()
    }

    func cachedSamples() async -> [ScanSample] {
        emitDemo()
        return DemoNetworks.samples
    }

    @MainActor
    func requestLocationIfNeeded() {}

    func refreshCache() {
        emitDemo()
    }

    func scan() {
        continuation.yield(.scanStarted)
        emitDemo()
        continuation.yield(.scanFinished(failed: false))
    }

    func setPower(_ on: Bool) {
        let state = InterfaceState(
            powerOn: on,
            ssid: on ? DemoNetworks.current : nil,
            rssi: on ? -44 : nil
        )
        continuation.yield(.powerChanged(state))
        if !on { continuation.yield(.stats(nil)) }
    }

    func join(ssid: String, password: String?, secure: Bool) {
        continuation.yield(.interface(InterfaceState(powerOn: true, ssid: ssid, rssi: -48)))
        continuation.yield(.joinFinished(ssid: ssid, outcome: .connected))
    }

    func setLive(_ on: Bool) {
        continuation.yield(.stats(on ? DemoNetworks.stats : nil))
    }

    private func emitDemo() {
        continuation.yield(.interface(InterfaceState(powerOn: true, ssid: DemoNetworks.current, rssi: -44)))
        continuation.yield(.samples(DemoNetworks.samples))
    }
}
