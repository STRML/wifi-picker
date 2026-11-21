import AppKit
import Observation
import WifiPickerCore

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: PickerPanel
    private let model: PickerModel
    private let dismissOnOutsideClick: Bool
    private var outsideClickMonitor: Any?

    init(model: PickerModel, dismissOnOutsideClick: Bool) {
        self.model = model
        self.dismissOnOutsideClick = dismissOnOutsideClick
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
        guard !model.isOpen, let anchor = anchorRect() else { return }
        Task {
            guard await model.beginSession() else { return }
            panel.place(under: anchor, height: desiredHeight(on: Self.screen(containing: anchor)))
            panel.makeKeyAndOrderFront(nil)
            installOutsideClickMonitor()
            model.refreshFromSystem()
        }
    }

    func close() {
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
            for: model.layout.rows(columns: Metrics.columns),
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
        guard dismissOnOutsideClick, outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func removeOutsideClickMonitor() {
        guard let monitor = outsideClickMonitor else { return }
        NSEvent.removeMonitor(monitor)
        outsideClickMonitor = nil
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
