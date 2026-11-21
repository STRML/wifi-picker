// Composes docs/screenshot.png: a drawn macOS menu bar and wallpaper with a panel capture under it.
// 1. Launch the app with `--demo --open-panel`, then capture the panel:
//    screencapture -x -l <window id> /tmp/panel.png
// 2. swift scripts/make-screenshot.swift /tmp/panel.png docs/screenshot.png
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let panel = NSImage(contentsOfFile: args[1]),
      let panelRep = panel.representations.first else {
    fatalError("usage: make-screenshot.swift <panel.png> <out.png>")
}

let scale: CGFloat = 2
let panelSize = NSSize(width: panelRep.pixelsWide, height: panelRep.pixelsHigh)
let panelShadowTop: CGFloat = 37
let barHeight = 24 * scale
let margin: CGFloat = 64
let leftRoom: CGFloat = 420
let canvas = NSSize(width: leftRoom + panelSize.width + margin, height: barHeight + 8 * scale - panelShadowTop + panelSize.height + margin)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let bounds = NSRect(origin: .zero, size: canvas)
NSBezierPath(roundedRect: bounds, xRadius: 28, yRadius: 28).addClip()

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: r, green: g, blue: b, alpha: a)
}

func drawWallpaper() {
    NSGradient(colors: [color(0.06, 0.09, 0.30), color(0.30, 0.14, 0.52), color(0.86, 0.38, 0.42)])!
        .draw(in: bounds, angle: -35)
    let glow = NSGradient(colors: [color(0.40, 0.75, 1.0, 0.45), color(0.40, 0.75, 1.0, 0)])!
    glow.draw(fromCenter: NSPoint(x: canvas.width * 0.18, y: canvas.height * 0.25), radius: 0,
              toCenter: NSPoint(x: canvas.width * 0.18, y: canvas.height * 0.25), radius: canvas.width * 0.45, options: [])
}

func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
    let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    return NSImage(size: base.size, flipped: false) { rect in
        base.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
}

func drawSymbol(_ image: NSImage, centerX: CGFloat) {
    let y = canvas.height - barHeight / 2 - image.size.height / 2
    image.draw(in: NSRect(x: centerX - image.size.width / 2, y: y, width: image.size.width, height: image.size.height))
}

@discardableResult
func drawText(_ text: String, x: CGFloat, bold: Bool = false, alignRight: Bool = false) -> CGFloat {
    let font = NSFont.systemFont(ofSize: 13 * scale, weight: bold ? .bold : .medium)
    let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
    let size = attributed.size()
    let originX = alignRight ? x - size.width : x
    attributed.draw(at: NSPoint(x: originX, y: canvas.height - barHeight / 2 - size.height / 2))
    return size.width
}

func drawMenuBar() -> CGFloat {
    color(0, 0, 0, 0.22).setFill()
    NSRect(x: 0, y: canvas.height - barHeight, width: canvas.width, height: barHeight).fill()

    var x: CGFloat = 20 * scale
    drawSymbol(symbol("apple.logo", size: 14 * scale, weight: .semibold), centerX: x)
    x += 22 * scale
    x += drawText("Finder", x: x, bold: true) + 20 * scale
    for item in ["File", "Edit", "View", "Go", "Window", "Help"] {
        x += drawText(item, x: x) + 20 * scale
    }

    var right = canvas.width - 14 * scale
    right -= drawText("Thu Nov 20  9:41 AM", x: right, alignRight: true) + 16 * scale
    let control = symbol("switch.2", size: 13 * scale, weight: .semibold)
    drawSymbol(control, centerX: right - control.size.width / 2)
    right -= control.size.width + 18 * scale
    let battery = symbol("battery.100percent", size: 13 * scale)
    drawSymbol(battery, centerX: right - battery.size.width / 2)
    right -= battery.size.width + 22 * scale

    let wifi = symbol("wifi", size: 14 * scale, weight: .semibold)
    let wifiCenter = right - wifi.size.width / 2
    let pill = NSRect(x: wifiCenter - 16 * scale, y: canvas.height - barHeight + 2 * scale, width: 32 * scale, height: barHeight - 4 * scale)
    color(1, 1, 1, 0.28).setFill()
    NSBezierPath(roundedRect: pill, xRadius: 6 * scale, yRadius: 6 * scale).fill()
    drawSymbol(wifi, centerX: wifiCenter)
    return wifiCenter
}

drawWallpaper()
let wifiCenter = drawMenuBar()

let panelTop = canvas.height - barHeight - 6 * scale + panelShadowTop
let panelX = min(max(wifiCenter - panelSize.width * 0.62, leftRoom * 0.35), canvas.width - panelSize.width)
panel.draw(in: NSRect(x: panelX, y: panelTop - panelSize.height, width: panelSize.width, height: panelSize.height))

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2]) \(Int(canvas.width))x\(Int(canvas.height))")
