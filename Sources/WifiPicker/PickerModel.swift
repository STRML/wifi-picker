import AppKit
import Observation
import WifiPickerCore

enum GridMode: Equatable {
    case networks
    case locationNeeded(LocationAccess)
    case wifiOff
}

@MainActor
@Observable
final class PickerModel {
    private(set) var store = NetworkStore()
    private(set) var layout: FrozenLayout
    private(set) var now = Date()
    private(set) var interface = InterfaceState(powerOn: true, ssid: nil, rssi: nil)
    private(set) var access: LocationAccess
    private(set) var scanning = false
    private(set) var scanFailed = false
    private(set) var focusedSSID: String?
    private(set) var isOpen = false

    @ObservationIgnored var onLayoutChange: (@MainActor () -> Void)?
    @ObservationIgnored var frameSink: (@MainActor ([String: CGRect]) -> Void)?
    @ObservationIgnored private var frames: [String: CGRect] = [:]
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private let service: WiFiService
    @ObservationIgnored private let gate: LocationGate

    init(service: WiFiService, gate: LocationGate) {
        self.service = service
        self.gate = gate
        access = gate.access
        var empty = NetworkStore()
        layout = LayoutEngine.freeze(&empty, now: Date())
        gate.onChange = { [weak self] access in self?.accessChanged(access) }
        Task { [weak self] in
            for await event in service.events {
                self?.handle(event)
            }
        }
    }

    var mode: GridMode {
        guard access == .granted else { return .locationNeeded(access) }
        return interface.powerOn ? .networks : .wifiOff
    }

    var canScan: Bool {
        access == .granted && interface.powerOn
    }

    var statusLine: String {
        if scanFailed { return "Scan failed" }
        if access != .granted { return "Location access needed" }
        if !interface.powerOn { return "Wi-Fi is off" }
        if scanning { return "Scanning…" }
        return interface.ssid == nil ? "Not connected" : "Connected"
    }

    var title: String {
        guard interface.powerOn, let ssid = interface.ssid else { return "Wi-Fi" }
        return ssid
    }

    func cell(for ssid: String) -> LayoutCell? {
        layout.cell(for: ssid, in: store, now: now)
    }

    func beginSession() {
        gate.requestIfNeeded()
        now = Date()
        layout = LayoutEngine.freeze(&store, now: now)
        focusedSSID = nil
        scanFailed = false
        isOpen = true
        startClock()
    }

    func refreshFromSystem() {
        service.refreshCache()
        rescan()
    }

    func endSession() {
        isOpen = false
        clockTask?.cancel()
        clockTask = nil
    }

    func rescan() {
        guard canScan, !scanning else { return }
        service.scan()
    }

    func setPower(_ on: Bool) {
        interface.powerOn = on
        service.setPower(on)
    }

    func moveFocus(_ direction: MoveDirection) {
        focusedSSID = layout.move(from: focusedSSID, direction, columns: Metrics.columns)
    }

    func cellFramesChanged(_ newFrames: [String: CGRect]) {
        frames = newFrames
        frameSink?(newFrames)
    }

    func activate(_ ssid: String) {}

    func requestLocation() {
        gate.requestIfNeeded()
    }

    private func handle(_ event: WiFiEvent) {
        switch event {
        case .samples(let samples): ingest(samples)
        case .interface(let state): apply(state)
        case .scanStarted: scanning = true
        case .scanFinished(let failed): finishScan(failed: failed)
        }
    }

    private func ingest(_ samples: [ScanSample]) {
        now = Date()
        store.ingest(samples, at: now)
        guard isOpen else { return }
        layout.absorb(store)
        onLayoutChange?()
    }

    private func apply(_ state: InterfaceState) {
        let turnedOn = state.powerOn && !interface.powerOn
        interface = state
        if turnedOn && isOpen { refreshFromSystem() }
    }

    private func finishScan(failed: Bool) {
        scanning = false
        scanFailed = failed
        guard frameSink != nil else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self else { return }
            frameSink?(frames)
        }
    }

    private func accessChanged(_ newAccess: LocationAccess) {
        access = newAccess
        guard newAccess == .granted else { return }
        isOpen ? refreshFromSystem() : service.refreshCache()
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.now = Date()
            }
        }
    }
}
