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

    init(model: PickerModel, frameDumper: FrameDumper? = nil) {
        self.model = model
        panel = PickerPanel(content: PickerRootView(model: model, frameDumper: frameDumper))
        super.init()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        panel.keyHandler = { [weak self] key in self?.model.handleKey(key) ?? false }
        model.onPanelEvent = { [weak self] event in self?.handlePanelEvent(event) }
        updateIcon()
        trackIcon()
    }

    func open() {
        guard anchorRect() != nil else { return }
        model.open()
    }

    func close() {
        model.close()
    }

    private func handlePanelEvent(_ event: PanelLifecycleEvent) {
        switch event {
        case .opened:
            guard let anchor = anchorRect() else {
                model.close()
                return
            }
            panel.place(under: anchor, height: desiredHeight(on: PickerPanel.screen(containing: anchor)))
            panel.makeKeyAndOrderFront(nil)
            installOutsideClickMonitor()
        case .layoutGrew:
            panel.growIfNeeded(to: desiredHeight(on: panel.screen))
        case .closed:
            panel.orderOut(nil)
            removeOutsideClickMonitor()
        }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            showMenu()
            return
        }
        switch model.panelPhase {
        case .closed:
            open()
        case .opening:
            close()
        case .open:
            panel.isVisible ? close() : panel.makeKeyAndOrderFront(nil)
        }
    }

    private func showMenu() {
        close()
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Wi-Fi Picker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func desiredHeight(on screen: NSScreen?) -> CGFloat {
        let visible = (screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        return Metrics.panelHeight(
            tallestColumnCount: model.tallestColumnCount,
            maxHeight: visible * Metrics.maxHeightFraction
        )
    }

    private func anchorRect() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
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
