import CoreWLAN
import Foundation
import WifiPickerCore

private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
}

final class MacWiFiEnvironment: NSObject, CWEventDelegate, PickerEnvironment, @unchecked Sendable {
    let events: AsyncStream<PickerEnvironmentEvent>
    let initialLocationAccess: LocationAccess

    private let continuation: AsyncStream<PickerEnvironmentEvent>.Continuation
    private let queue = DispatchQueue(label: "wifi-picker.service", qos: .userInitiated)
    private let scanQueue = DispatchQueue(label: "wifi-picker.scan", qos: .userInitiated)
    private let client = CWWiFiClient.shared()
    private let statsReader = LinkStatsReader()
    private let locationGate: LocationGate

    private var networks: [String: (network: CWNetwork, lastSeen: Date)] = [:]
    private var lastInterface: InterfaceState?
    private var scanning = false
    private var live = false

    @MainActor
    override init() {
        let pair = AsyncStream.makeStream(of: PickerEnvironmentEvent.self, bufferingPolicy: .unbounded)
        events = pair.stream
        continuation = pair.continuation
        let gate = LocationGate()
        locationGate = gate
        initialLocationAccess = gate.access
        super.init()
        gate.onChange = { [continuation] access in
            continuation.yield(.locationAccess(access))
        }
    }

    func start() {
        queue.async { [self] in
            client.delegate = self
            let monitored: [CWEventType] = [
                .scanCacheUpdated, .powerDidChange, .ssidDidChange, .linkDidChange,
            ]
            for event in monitored {
                try? client.startMonitoringEvent(with: event)
            }
            publishInterface()
        }
    }

    func cachedSamples() async -> [ScanSample] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                publishInterface()
                continuation.resume(returning: currentCacheSamples())
            }
        }
    }

    @MainActor
    func requestLocationIfNeeded() {
        locationGate.requestIfNeeded()
    }

    func refreshCache() {
        queue.async { [self] in
            publishInterface()
            readCache()
        }
    }

    func scan() {
        queue.async { [self] in
            guard !scanning else { return }
            scanning = true
            continuation.yield(.scanStarted)
            scanQueue.async { [self] in
                let found = fetchScan()
                queue.async { [self] in finishScan(found) }
            }
        }
    }

    func setPower(_ on: Bool) {
        queue.async { [self] in
            try? client.interface()?.setPower(on)
            publishInterface(force: true, powerSettled: true)
        }
    }

    func join(ssid: String, password: String?, secure: Bool) {
        queue.async { [self] in
            let target = networks[ssid].map { UncheckedBox(value: $0.network) }
            scanQueue.async { [self] in
                let outcome = associate(target, password: password, secure: secure)
                queue.async { [self] in
                    publishInterface()
                    continuation.yield(.joinFinished(ssid: ssid, outcome: outcome))
                }
            }
        }
    }

    func setLive(_ on: Bool) {
        queue.async { [self] in
            live = on
            if on {
                try? client.startMonitoringEvent(with: .linkQualityDidChange)
                publishStats()
            } else {
                try? client.stopMonitoringEvent(with: .linkQualityDidChange)
            }
        }
    }

    func scanCacheUpdatedForWiFiInterface(withName interfaceName: String) {
        queue.async { [self] in
            if live {
                readCache()
            } else {
                continuation.yield(.cacheUpdated)
            }
        }
    }

    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        queue.async { [self] in publishInterface() }
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        queue.async { [self] in publishInterface() }
    }

    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        queue.async { [self] in publishInterface() }
    }

    func linkQualityDidChangeForWiFiInterface(withName interfaceName: String, rssi: Int, transmitRate: Double) {
        queue.async { [self] in
            publishInterface()
            publishStats()
        }
    }

    private func publishStats() {
        guard live else { return }
        continuation.yield(.stats(client.interface().flatMap { statsReader.read(from: $0) }))
    }

    private func associate(_ target: UncheckedBox<CWNetwork>?, password: String?, secure: Bool) -> JoinOutcome {
        guard let interface = client.interface(), let network = target?.value else {
            return .failed(String(localized: "Network not in range"))
        }
        do {
            try interface.associate(to: network, password: password)
            return .connected
        } catch let error as NSError {
            return JoinPolicy.outcome(
                forErrorCode: error.code,
                fallbackMessage: error.localizedDescription,
                hadPassword: password != nil,
                secure: secure
            )
        }
    }

    private func fetchScan() -> UncheckedBox<Set<CWNetwork>>? {
        guard let interface = client.interface(), interface.powerOn() else { return nil }
        guard let found = try? interface.scanForNetworks(withSSID: nil) else { return nil }
        return UncheckedBox(value: found)
    }

    private func finishScan(_ found: UncheckedBox<Set<CWNetwork>>?) {
        scanning = false
        publishInterface()
        guard let found else {
            continuation.yield(.scanFinished(failed: true))
            return
        }
        continuation.yield(.samples(samples(from: Array(found.value))))
        continuation.yield(.scanFinished(failed: false))
    }

    private func readCache() {
        continuation.yield(.samples(currentCacheSamples()))
    }

    private func currentCacheSamples() -> [ScanSample] {
        guard let interface = client.interface(), interface.powerOn() else { return [] }
        return samples(from: Array(interface.cachedScanResults() ?? []))
    }

    private func samples(from found: [CWNetwork]) -> [ScanSample] {
        let now = Date()
        let known = knownSSIDs()
        var samples: [ScanSample] = []
        var strongest: [String: CWNetwork] = [:]
        for network in found {
            guard let ssid = network.ssid, !ssid.isEmpty else { continue }
            samples.append(
                ScanSample(
                    ssid: ssid,
                    bssid: network.bssid ?? "",
                    rssi: network.rssiValue,
                    secure: !network.supportsSecurity(.none),
                    known: known.contains(ssid)
                )
            )
            if let current = strongest[ssid] {
                if Self.isStronger(network, than: current) { strongest[ssid] = network }
            } else {
                strongest[ssid] = network
            }
        }
        for (ssid, network) in strongest {
            networks[ssid] = (network, now)
        }
        networks = networks.filter { now.timeIntervalSince($0.value.lastSeen) <= PickerSession.pruneInterval }
        return samples
    }

    private static func isStronger(_ candidate: CWNetwork, than existing: CWNetwork) -> Bool {
        if candidate.rssiValue != existing.rssiValue {
            return candidate.rssiValue > existing.rssiValue
        }
        return (candidate.bssid ?? "") < (existing.bssid ?? "")
    }

    private func knownSSIDs() -> Set<String> {
        guard let profiles = client.interface()?.configuration()?.networkProfiles else { return [] }
        return Set(profiles.array.compactMap { ($0 as? CWNetworkProfile)?.ssid })
    }

    private func publishInterface(force: Bool = false, powerSettled: Bool = false) {
        guard let interface = client.interface() else { return }
        let powerOn = interface.powerOn()
        let rssi = powerOn ? interface.rssiValue() : 0
        let state = InterfaceState(
            powerOn: powerOn,
            ssid: powerOn ? interface.ssid() : nil,
            rssi: rssi == 0 ? nil : rssi
        )
        guard force || state != lastInterface else { return }
        lastInterface = state
        continuation.yield(powerSettled ? .powerChanged(state) : .interface(state))
    }
}
