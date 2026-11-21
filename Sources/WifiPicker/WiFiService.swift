import CoreWLAN
import Foundation
import WifiPickerCore

struct InterfaceState: Sendable, Equatable {
    var powerOn: Bool
    var ssid: String?
    var rssi: Int?
}

enum WiFiEvent: Sendable {
    case samples([ScanSample])
    case interface(InterfaceState)
    case scanStarted
    case scanFinished(failed: Bool)
    case joinFinished(ssid: String, outcome: JoinOutcome)
    case stats(LinkStats?)
}

private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
}

final class WiFiService: NSObject, CWEventDelegate, @unchecked Sendable {
    let events: AsyncStream<WiFiEvent>
    private let continuation: AsyncStream<WiFiEvent>.Continuation
    private let queue = DispatchQueue(label: "wifi-picker.service", qos: .userInitiated)
    private let scanQueue = DispatchQueue(label: "wifi-picker.scan", qos: .userInitiated)
    private let client = CWWiFiClient.shared()
    private var networks: [String: CWNetwork] = [:]
    private var lastInterface: InterfaceState?
    private let scanLock = NSLock()
    private var scanning = false
    private let demo: Bool
    private var live = false

    init(demo: Bool = false) {
        let pair = AsyncStream.makeStream(of: WiFiEvent.self, bufferingPolicy: .unbounded)
        events = pair.stream
        continuation = pair.continuation
        self.demo = demo
        super.init()
    }

    func start() {
        guard !demo else { return emitDemo() }
        queue.async { [self] in
            client.delegate = self
            let monitored: [CWEventType] = [
                .scanCacheUpdated, .powerDidChange, .ssidDidChange, .linkDidChange,
            ]
            for event in monitored {
                try? client.startMonitoringEvent(with: event)
            }
            publishInterface()
            readCache()
        }
    }

    func refreshCache() {
        guard !demo else { return emitDemo() }
        queue.async { [self] in
            publishInterface()
            readCache()
        }
    }

    func scan() {
        guard !demo else { return emitDemo() }
        guard beginScan() else { return }
        continuation.yield(.scanStarted)
        scanQueue.async { [self] in
            let found = fetchScan()
            queue.async { [self] in finishScan(found) }
        }
    }

    func setPower(_ on: Bool) {
        guard !demo else { return }
        queue.async { [self] in
            try? client.interface()?.setPower(on)
            publishInterface(force: true)
        }
    }

    func join(ssid: String, password: String?, secure: Bool) {
        guard !demo else { return }
        queue.async { [self] in
            let outcome = associate(ssid: ssid, password: password, secure: secure)
            publishInterface()
            continuation.yield(.joinFinished(ssid: ssid, outcome: outcome))
        }
    }

    func scanCacheUpdatedForWiFiInterface(withName interfaceName: String) {
        queue.async { [self] in readCache() }
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

    func setLive(_ on: Bool) {
        guard !demo else {
            continuation.yield(.stats(on ? DemoNetworks.stats : nil))
            return
        }
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

    private func publishStats() {
        guard live else { return }
        continuation.yield(.stats(client.interface().flatMap(LinkStats.read)))
    }

    private func associate(ssid: String, password: String?, secure: Bool) -> JoinOutcome {
        guard let interface = client.interface(), let network = networks[ssid] else {
            return .failed("Network not in range")
        }
        do {
            try interface.associate(to: network, password: password)
            return .connected
        } catch let error as NSError {
            return JoinPolicy.outcome(
                forErrorCode: error.code,
                message: error.localizedDescription,
                hadPassword: password != nil,
                secure: secure
            )
        }
    }

    private func beginScan() -> Bool {
        scanLock.lock()
        defer { scanLock.unlock() }
        guard !scanning else { return false }
        scanning = true
        return true
    }

    private func endScan() {
        scanLock.lock()
        scanning = false
        scanLock.unlock()
    }

    private func fetchScan() -> UncheckedBox<Set<CWNetwork>>? {
        guard let interface = client.interface(), interface.powerOn() else { return nil }
        guard let found = try? interface.scanForNetworks(withSSID: nil) else { return nil }
        return UncheckedBox(value: found)
    }

    private func finishScan(_ found: UncheckedBox<Set<CWNetwork>>?) {
        endScan()
        publishInterface()
        guard let found else {
            continuation.yield(.scanFinished(failed: true))
            return
        }
        ingest(Array(found.value))
        continuation.yield(.scanFinished(failed: false))
    }

    private func emitDemo() {
        continuation.yield(.interface(InterfaceState(powerOn: true, ssid: DemoNetworks.current, rssi: -44)))
        continuation.yield(.samples(DemoNetworks.samples))
    }

    private func readCache() {
        guard let interface = client.interface(), interface.powerOn() else {
            continuation.yield(.samples([]))
            return
        }
        ingest(Array(interface.cachedScanResults() ?? []))
    }

    private func ingest(_ found: [CWNetwork]) {
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
                    band: Band(network.wlanChannel?.channelBand),
                    secure: !network.supportsSecurity(.none),
                    known: known.contains(ssid)
                )
            )
            if network.rssiValue >= (strongest[ssid]?.rssiValue ?? Int.min) {
                strongest[ssid] = network
            }
        }
        networks.merge(strongest) { _, latest in latest }
        continuation.yield(.samples(samples))
    }

    private func knownSSIDs() -> Set<String> {
        guard let profiles = client.interface()?.configuration()?.networkProfiles else { return [] }
        return Set(profiles.array.compactMap { ($0 as? CWNetworkProfile)?.ssid })
    }

    private func publishInterface(force: Bool = false) {
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
        continuation.yield(.interface(state))
    }
}

private extension Band {
    init(_ band: CWChannelBand?) {
        switch band {
        case .band2GHz: self = .ghz2
        case .band5GHz: self = .ghz5
        case .band6GHz: self = .ghz6
        default: self = .unknown
        }
    }
}
