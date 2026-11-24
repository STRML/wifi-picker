import Foundation
import Observation

public struct PasswordRequest: Equatable, Sendable {
    public let ssid: String
    public let error: String?

    public init(ssid: String, error: String?) {
        self.ssid = ssid
        self.error = error
    }
}

public enum GridMode: Equatable, Sendable {
    case networks
    case locationNeeded(LocationAccess)
    case wifiOff
}

public enum PanelPhase: Equatable, Sendable {
    case closed
    case opening
    case open
}

public enum ScanState: Equatable, Sendable {
    case idle
    case scanning
    case failed
}

public enum JoinState: Equatable, Sendable {
    case idle
    case promptingPassword(ssid: String, error: String?)
    case joining(ssid: String, fromPasswordSheet: Bool)
    case failed(ssid: String, message: String)
}

public enum PanelLifecycleEvent: Equatable, Sendable {
    case opened
    case layoutGrew
    case closed
}

@MainActor
@Observable
public final class PickerModel {
    public static let cacheFreshness: TimeInterval = 120

    private var session = PickerSession()
    public private(set) var now: Date
    public private(set) var panelPhase: PanelPhase = .closed
    public private(set) var interface = InterfaceState(powerOn: true, ssid: nil, rssi: nil)
    public private(set) var pendingPower: Bool?
    public private(set) var access: LocationAccess
    public private(set) var scanState: ScanState = .idle
    public private(set) var joinState: JoinState = .idle
    public private(set) var focusedSSID: String?
    public private(set) var stats: LinkStats?

    @ObservationIgnored public var onPanelEvent: (@MainActor (PanelLifecycleEvent) -> Void)?
    @ObservationIgnored public var onScanFinished: (@MainActor () -> Void)?
    @ObservationIgnored private var lastCacheUpdate: Date?
    @ObservationIgnored private var openGeneration: UInt64 = 0
    @ObservationIgnored private var openTask: Task<Bool, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private let environment: any PickerEnvironment
    @ObservationIgnored private let clock: PickerClock

    public init(environment: any PickerEnvironment, clock: PickerClock = .live) {
        self.environment = environment
        self.clock = clock
        self.now = clock.now()
        self.access = environment.initialLocationAccess
        Task { [weak self] in
            for await event in environment.events {
                self?.handle(event)
            }
        }
    }

    public var columns: [LayoutColumn] { session.columns }
    public var tallestColumnCount: Int { session.tallestColumnCount }
    public var isOpen: Bool { panelPhase == .open }
    public var displayedPower: Bool { pendingPower ?? interface.powerOn }

    public var mode: GridMode {
        guard access == .granted else { return .locationNeeded(access) }
        return interface.powerOn ? .networks : .wifiOff
    }

    public var canScan: Bool {
        access == .granted && interface.powerOn
    }

    public var canRescan: Bool {
        canScan && scanState != .scanning && joiningSSID == nil
    }

    public var scanning: Bool {
        scanState == .scanning
    }

    public var joiningSSID: String? {
        if case .joining(let ssid, _) = joinState { return ssid }
        return nil
    }

    public var passwordRequest: PasswordRequest? {
        switch joinState {
        case .promptingPassword(let ssid, let error):
            return PasswordRequest(ssid: ssid, error: error)
        case .joining(let ssid, fromPasswordSheet: true):
            return PasswordRequest(ssid: ssid, error: nil)
        case .idle, .joining(_, fromPasswordSheet: false), .failed:
            return nil
        }
    }

    public var statusIsError: Bool {
        switch joinState {
        case .joining: false
        case .failed: true
        case .idle, .promptingPassword: scanState == .failed
        }
    }

    public var isBusy: Bool {
        scanState == .scanning || joiningSSID != nil
    }

    public var statusLine: String {
        switch joinState {
        case .joining(let ssid, _):
            return "Joining \(ssid)…"
        case .failed(_, let message):
            return message
        case .idle, .promptingPassword:
            break
        }
        if scanState == .failed { return "Scan failed" }
        if access != .granted { return "Location access needed" }
        if !interface.powerOn { return "Wi-Fi is off" }
        if scanState == .scanning { return "Scanning…" }
        return interface.ssid == nil ? "Not connected" : "Connected"
    }

    public var title: String {
        guard interface.powerOn, let ssid = interface.ssid else { return "Wi-Fi" }
        return ssid
    }

    public func cell(for ssid: String) -> LayoutCell? {
        session.cell(for: ssid, at: now)
    }

    @discardableResult
    public func open() -> Task<Bool, Never> {
        if let existing = openTask { return existing }
        guard panelPhase == .closed else { return Task { false } }
        panelPhase = .opening
        openGeneration &+= 1
        let generation = openGeneration
        environment.requestLocationIfNeeded()
        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }
            return await self.runOpen(generation: generation)
        }
        openTask = task
        return task
    }

    public func close() {
        guard panelPhase != .closed else { return }
        openGeneration &+= 1
        openTask?.cancel()
        openTask = nil
        panelPhase = .closed
        session.close()
        clockTask?.cancel()
        clockTask = nil
        environment.setLive(false)
        stats = nil
        switch joinState {
        case .joining(let ssid, _):
            joinState = .joining(ssid: ssid, fromPasswordSheet: false)
        case .idle, .promptingPassword, .failed:
            joinState = .idle
        }
        onPanelEvent?(.closed)
    }

    public func rescan() {
        guard canRescan else { return }
        environment.scan()
    }

    public func setPower(_ on: Bool) {
        pendingPower = on
        environment.setPower(on)
    }

    public func moveFocus(_ direction: MoveDirection) {
        focusedSSID = session.move(from: focusedSSID, direction)
    }

    public func activate(_ ssid: String) {
        guard ssid != interface.ssid else { return }
        switch joinState {
        case .idle, .failed: break
        case .promptingPassword, .joining: return
        }
        guard let cell = cell(for: ssid), !cell.dimmed else { return }
        if JoinPolicy.needsPasswordUpFront(secure: cell.entry.secure, known: cell.entry.known) {
            joinState = .promptingPassword(ssid: ssid, error: nil)
            return
        }
        startJoin(ssid, password: nil, secure: cell.entry.secure, fromPasswordSheet: false)
    }

    public func activateFocused() {
        guard let focusedSSID else { return }
        activate(focusedSSID)
    }

    public func submitPassword(_ password: String) {
        guard case .promptingPassword(let ssid, _) = joinState, !password.isEmpty else { return }
        startJoin(ssid, password: password, secure: true, fromPasswordSheet: true)
    }

    public func dismissPasswordRequest() {
        guard case .promptingPassword = joinState else { return }
        joinState = .idle
    }

    public func handleKey(_ key: PanelKey) -> Bool {
        switch key {
        case .escape:
            if case .promptingPassword = joinState {
                joinState = .idle
            } else {
                close()
            }
            return true
        case .arrow(let direction):
            guard passwordRequest == nil else { return false }
            moveFocus(direction)
            return true
        case .confirm:
            guard passwordRequest == nil else { return false }
            activateFocused()
            return true
        }
    }

    public func requestLocation() {
        environment.requestLocationIfNeeded()
    }

    private func runOpen(generation: UInt64) async -> Bool {
        defer {
            if openGeneration == generation { openTask = nil }
        }
        let cached = await environment.cachedSamples()
        guard !Task.isCancelled, panelPhase == .opening, openGeneration == generation else {
            return false
        }
        now = clock.now()
        session.ingest(cached, at: now)
        guard session.open(at: now) else {
            panelPhase = .closed
            return false
        }
        panelPhase = .open
        focusedSSID = nil
        if scanState == .failed { scanState = .idle }
        if case .joining = joinState {
            // Preserve an in-flight join started before closing.
        } else {
            joinState = .idle
        }
        startClock()
        environment.setLive(true)
        onPanelEvent?(.opened)
        scanIfCacheStale()
        return true
    }

    private func scanIfCacheStale() {
        guard canRescan else { return }
        guard shouldScanOnOpen(lastCacheUpdate: lastCacheUpdate, now: now) else { return }
        environment.scan()
    }

    private func shouldScanOnOpen(lastCacheUpdate: Date?, now: Date) -> Bool {
        guard let lastCacheUpdate else { return true }
        return now.timeIntervalSince(lastCacheUpdate) > Self.cacheFreshness
    }

    private func refreshFromSystem() {
        environment.refreshCache()
        rescan()
    }

    private func startJoin(_ ssid: String, password: String?, secure: Bool, fromPasswordSheet: Bool) {
        joinState = .joining(ssid: ssid, fromPasswordSheet: fromPasswordSheet)
        environment.join(ssid: ssid, password: password, secure: secure)
    }

    private func handle(_ event: PickerEnvironmentEvent) {
        switch event {
        case .samples(let samples):
            ingest(samples)
        case .cacheUpdated:
            lastCacheUpdate = clock.now()
        case .interface(let state):
            apply(state, powerSettled: false)
        case .powerChanged(let state):
            apply(state, powerSettled: true)
        case .locationAccess(let newAccess):
            accessChanged(newAccess)
        case .scanStarted:
            scanState = .scanning
        case .scanFinished(let failed):
            finishScan(failed: failed)
        case .joinFinished(let ssid, let outcome):
            finishJoin(ssid, outcome)
        case .stats(let value):
            stats = value
        }
    }

    private func finishJoin(_ ssid: String, _ outcome: JoinOutcome) {
        guard case .joining(let current, _) = joinState, current == ssid else { return }
        guard isOpen else {
            joinState = .idle
            return
        }
        switch outcome {
        case .connected:
            joinState = .idle
        case .needsPassword:
            joinState = .promptingPassword(ssid: ssid, error: nil)
        case .wrongPassword:
            joinState = .promptingPassword(ssid: ssid, error: "Wrong password")
        case .failed(let message):
            joinState = .failed(ssid: ssid, message: message)
        }
    }

    private func ingest(_ samples: [ScanSample]) {
        now = clock.now()
        lastCacheUpdate = now
        session.ingest(samples, at: now)
        guard isOpen else { return }
        onPanelEvent?(.layoutGrew)
    }

    private func apply(_ state: InterfaceState, powerSettled: Bool) {
        let turnedOn = state.powerOn && !interface.powerOn
        if powerSettled || pendingPower == state.powerOn {
            pendingPower = nil
        }
        interface = state
        if !state.powerOn {
            if scanState == .failed { scanState = .idle }
            if case .promptingPassword = joinState { joinState = .idle }
        }
        if turnedOn && isOpen {
            refreshFromSystem()
        }
    }

    private func finishScan(failed: Bool) {
        lastCacheUpdate = clock.now()
        scanState = failed ? .failed : .idle
        onScanFinished?()
    }

    private func accessChanged(_ newAccess: LocationAccess) {
        access = newAccess
        guard newAccess == .granted, isOpen else { return }
        refreshFromSystem()
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await self.clock.sleep(.seconds(5))
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                self.now = self.clock.now()
            }
        }
    }
}
