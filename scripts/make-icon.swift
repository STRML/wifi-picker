// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.10, green: 0.55, blue: 1.0, alpha: 1),
                        NSColor(red: 0.36, green: 0.22, blue: 0.95, alpha: 1)])!.draw(in: path, angle: -60)
    let grid = tile.width * 0.2
    let gap = tile.width * 0.035
    let origin = NSPoint(x: tile.midX - (3 * grid + 2 * gap) / 2, y: tile.minY + tile.height * 0.14)
    for col in 0..<3 {
        for row in 0..<3 {
            let r = NSRect(x: origin.x + CGFloat(col) * (grid + gap), y: origin.y + CGFloat(row) * (grid * 0.42 + gap),
                           width: grid, height: grid * 0.42)
            NSColor.white.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
        }
    }
    let config = NSImage.SymbolConfiguration(pointSize: tile.width * 0.36, weight: .bold)
    if let symbol = NSImage(systemSymbolName: "wifi", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let size = tinted.size
        tinted.draw(in: NSRect(x: tile.midX - size.width / 2, y: tile.minY + tile.height * 0.5,
                               width: size.width, height: size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in sizes where size <= 512 {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(1024).write(to: root.appendingPathComponent("docs/icon.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote Resources/AppIcon.icns and docs/icon.png" : "iconutil failed")
