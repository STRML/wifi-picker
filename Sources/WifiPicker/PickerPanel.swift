import AppKit
import SwiftUI
import WifiPickerCore

@MainActor
final class PickerPanel: NSPanel {
    var keyHandler: (@MainActor (PanelKey) -> Bool)?
    private var topEdge: CGFloat = 0

    init<Content: View>(content: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.panelWidth, height: Metrics.minContentHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        contentView = Self.makeContent(content)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    static func screen(containing rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) }
    }

    func place(under anchor: NSRect, height: CGFloat) {
        let visible = (Self.screen(containing: anchor) ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let left = min(
            max(anchor.midX - Metrics.panelWidth / 2, visible.minX + Metrics.screenMargin),
            visible.maxX - Metrics.panelWidth - Metrics.screenMargin
        )
        topEdge = min(anchor.minY - Metrics.statusItemGap, visible.maxY)
        setFrame(NSRect(x: left, y: topEdge - height, width: Metrics.panelWidth, height: height), display: true)
    }

    func growIfNeeded(to height: CGFloat) {
        guard height > frame.height else { return }
        setFrame(
            NSRect(x: frame.minX, y: topEdge - height, width: Metrics.panelWidth, height: height),
            display: true,
            animate: false
        )
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown, let key = Self.key(for: event), keyHandler?(key) == true else {
            super.sendEvent(event)
            return
        }
    }

    private static func key(for event: NSEvent) -> PanelKey? {
        let blocked: NSEvent.ModifierFlags = [.command, .option, .control]
        guard event.modifierFlags.isDisjoint(with: blocked) else { return nil }
        switch event.keyCode {
        case 53: return .escape
        case 36, 76: return .confirm
        case 123: return .arrow(.left)
        case 124: return .arrow(.right)
        case 125: return .arrow(.down)
        case 126: return .arrow(.up)
        default: return nil
        }
    }

    private static func makeContent<Content: View>(_ content: Content) -> NSView {
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.maskImage = roundedMask(radius: Metrics.cornerRadius)

        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
