import AppKit
import Observation
import WifiPickerCore

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: PickerPanel
    private let model: PickerModel
    private var outsideClickMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var openTask: Task<Void, Never>?

    init(model: PickerModel) {
        self.model = model
        panel = PickerPanel(content: PickerRootView(model: model))
        super.init()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        panel.keyHandler = { [weak self] key in self?.handle(key) ?? false }
        model.onLayoutChange = { [weak self] in self?.growPanel() }
        updateIcon()
        trackIcon()
    }

    func open() {
        guard !model.isOpen, openTask == nil, let anchor = anchorRect() else { return }
        openTask = Task {
            defer { openTask = nil }
            guard await model.beginSession() else { return }
            guard !Task.isCancelled else {
                model.endSession()
                return
            }
            panel.place(under: anchor, height: desiredHeight(on: Self.screen(containing: anchor)))
            panel.makeKeyAndOrderFront(nil)
            installOutsideClickMonitor()
            model.scanOnOpen()
        }
    }

    func close() {
        openTask?.cancel()
        guard model.isOpen else { return }
        panel.orderOut(nil)
        model.endSession()
        removeOutsideClickMonitor()
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            showMenu()
            return
        }
        guard openTask == nil else { return close() }
        guard model.isOpen else { return open() }
        panel.isVisible ? close() : panel.makeKeyAndOrderFront(nil)
    }

    private func showMenu() {
        close()
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Wi-Fi Picker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func handle(_ key: PanelKey) -> Bool {
        switch key {
        case .escape:
            if !model.dismissPasswordRequest() { close() }
            return true
        case .arrow(let direction):
            guard model.passwordRequest == nil else { return false }
            model.moveFocus(direction)
            return true
        case .confirm:
            guard model.passwordRequest == nil else { return false }
            model.activateFocused()
            return true
        }
    }

    private func growPanel() {
        panel.growIfNeeded(to: desiredHeight(on: panel.screen))
    }

    private func desiredHeight(on screen: NSScreen?) -> CGFloat {
        let visible = (screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        return Metrics.panelHeight(
            for: model.layout,
            maxHeight: visible * Metrics.maxHeightFraction
        )
    }

    private func anchorRect() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private static func screen(containing rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) }
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Task { @MainActor in self?.close() }
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
        }
    }

    private func updateIcon() {
        let state = model.interface
        let symbol = state.powerOn ? "wifi" : "wifi.slash"
        let level = state.rssi.map(SignalLevel.value(forRSSI:)) ?? 0
        let image = NSImage(
            systemSymbolName: symbol,
            variableValue: level,
            accessibilityDescription: "Wi-Fi"
        )
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func trackIcon() {
        withObservationTracking {
            _ = model.interface
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateIcon()
                self?.trackIcon()
            }
        }
    }
}
