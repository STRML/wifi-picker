import AppKit
import Observation
import WifiPickerCore

struct PasswordRequest: Equatable {
    let ssid: String
    var error: String?
}

enum GridMode: Equatable {
    case networks
    case locationNeeded(LocationAccess)
    case wifiOff
}

@MainActor
@Observable
final class PickerModel {
    private var session = PickerSession()
    private(set) var now = Date()
    private(set) var interface = InterfaceState(powerOn: true, ssid: nil, rssi: nil)
    private(set) var requestedPower: Bool?
    private(set) var access: LocationAccess
    private(set) var scanning = false
    private(set) var scanFailed = false
    private(set) var focusedSSID: String?
    private(set) var joiningSSID: String?
    private(set) var joinError: String?
    private(set) var passwordRequest: PasswordRequest?
    private(set) var stats: LinkStats?

    @ObservationIgnored var onLayoutChange: (@MainActor () -> Void)?
    @ObservationIgnored var frameSink: (@MainActor (String, [String: CellFrames]) -> Void)?
    @ObservationIgnored private var frames: [String: CellFrames] = [:]
    @ObservationIgnored private var opening = false
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private let service: WiFiService
    @ObservationIgnored private let gate: LocationGate

    init(service: WiFiService, gate: LocationGate) {
        self.service = service
        self.gate = gate
        access = gate.access
        gate.onChange = { [weak self] access in self?.accessChanged(access) }
        Task { [weak self] in
            for await event in service.events {
                self?.handle(event)
            }
        }
    }

    var store: NetworkStore { session.store }
    var layout: FrozenLayout { session.layout }
    var isOpen: Bool { session.isOpen }

    var mode: GridMode {
        guard access == .granted else { return .locationNeeded(access) }
        return interface.powerOn ? .networks : .wifiOff
    }

    var canScan: Bool {
        access == .granted && interface.powerOn
    }

    var statusIsError: Bool {
        joiningSSID == nil && (joinError != nil || scanFailed)
    }

    var isBusy: Bool {
        scanning || joiningSSID != nil
    }

    var statusLine: String {
        if let joiningSSID { return "Joining \(joiningSSID)…" }
        if let joinError { return joinError }
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

    func beginSession() async -> Bool {
        guard !isOpen, !opening else { return false }
        opening = true
        defer { opening = false }
        gate.requestIfNeeded()
        let cached = await service.cachedSamples()
        guard !Task.isCancelled else { return false }
        now = Date()
        session.ingest(cached, at: now)
        guard session.open(at: now) else { return false }
        focusedSSID = nil
        scanFailed = false
        joinError = nil
        passwordRequest = nil
        startClock()
        service.setLive(true)
        return true
    }

    func refreshFromSystem() {
        service.refreshCache()
        rescan()
    }

    func scanOnOpen() {
        guard canScan, !scanning, joiningSSID == nil else { return }
        service.scanIfCacheStale()
    }

    func endSession() {
        session.close()
        passwordRequest = nil
        clockTask?.cancel()
        clockTask = nil
        service.setLive(false)
        stats = nil
    }

    func rescan() {
        guard canScan, !scanning, joiningSSID == nil else { return }
        service.scan()
    }

    func setPower(_ on: Bool) {
        requestedPower = on
        service.setPower(on)
    }

    func moveFocus(_ direction: MoveDirection) {
        focusedSSID = layout.move(from: focusedSSID, direction)
    }

    func cellFramesChanged(_ newFrames: [String: CellFrames]) {
        frames = newFrames
        frameSink?("layout", newFrames)
    }

    func activate(_ ssid: String) {
        guard joiningSSID == nil, passwordRequest == nil, ssid != interface.ssid else { return }
        guard let cell = cell(for: ssid), !cell.dimmed else { return }
        joinError = nil
        guard !JoinPolicy.needsPasswordUpFront(secure: cell.entry.secure, known: cell.entry.known) else {
            passwordRequest = PasswordRequest(ssid: ssid, error: nil)
            return
        }
        startJoin(ssid, password: nil, secure: cell.entry.secure)
    }

    func activateFocused() {
        guard let focusedSSID else { return }
        activate(focusedSSID)
    }

    func submitPassword(_ password: String) {
        guard let request = passwordRequest, joiningSSID == nil, !password.isEmpty else { return }
        passwordRequest = PasswordRequest(ssid: request.ssid, error: nil)
        startJoin(request.ssid, password: password, secure: true)
    }

    func dismissPasswordRequest() -> Bool {
        guard passwordRequest != nil, joiningSSID == nil else { return false }
        passwordRequest = nil
        return true
    }

    func requestLocation() {
        gate.requestIfNeeded()
    }

    private func handle(_ event: WiFiEvent) {
        switch event {
        case .samples(let samples): ingest(samples)
        case .interface(let state): apply(state)
        case .scanStarted: scanning = true
        case .scanFinished(let failed): finishScan(failed: failed)
        case .joinFinished(let ssid, let outcome): finishJoin(ssid, outcome)
        case .stats(let value): stats = value
        }
    }

    private func startJoin(_ ssid: String, password: String?, secure: Bool) {
        joiningSSID = ssid
        service.join(ssid: ssid, password: password, secure: secure)
    }

    private func finishJoin(_ ssid: String, _ outcome: JoinOutcome) {
        joiningSSID = nil
        guard isOpen else { return }
        switch outcome {
        case .connected:
            passwordRequest = nil
        case .needsPassword:
            passwordRequest = PasswordRequest(ssid: ssid, error: nil)
        case .wrongPassword:
            passwordRequest = PasswordRequest(ssid: ssid, error: "Wrong password")
        case .failed:
            passwordRequest = nil
            joinError = "Couldn’t join \(ssid)"
        }
    }

    private func ingest(_ samples: [ScanSample]) {
        now = Date()
        session.ingest(samples, at: now)
        guard isOpen else { return }
        onLayoutChange?()
    }

    private func apply(_ state: InterfaceState) {
        let turnedOn = state.powerOn && !interface.powerOn
        requestedPower = nil
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
            frameSink?("scan-finished", frames)
        }
    }

    private func accessChanged(_ newAccess: LocationAccess) {
        access = newAccess
        guard newAccess == .granted, isOpen else { return }
        refreshFromSystem()
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
