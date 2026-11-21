import CoreGraphics
import Foundation

@MainActor
final class FrameDumper {
    private struct Cell: Encodable {
        let ssid: String
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let gridX: Double
        let gridY: Double
    }

    private struct Pass: Encodable {
        let pass: Int
        let reason: String
        let time: String
        let cells: [Cell]
    }

    private let url: URL
    private let encoder = JSONEncoder()
    private var pass = 0

    init(path: String) {
        url = URL(fileURLWithPath: path)
        encoder.outputFormatting = [.sortedKeys]
        FileManager.default.createFile(atPath: path, contents: nil)
    }

    func write(reason: String, frames: [String: CellFrames]) {
        let cells = frames
            .map { Cell(ssid: $0.key, x: $0.value.window.minX, y: $0.value.window.minY, width: $0.value.window.width, height: $0.value.window.height, gridX: $0.value.grid.minX, gridY: $0.value.grid.minY) }
            .sorted { ($0.y, $0.x, $0.ssid) < ($1.y, $1.x, $1.ssid) }
        pass += 1
        let record = Pass(pass: pass, reason: reason, time: ISO8601DateFormatter().string(from: Date()), cells: cells)
        guard var line = try? encoder.encode(record), let handle = try? FileHandle(forWritingTo: url) else { return }
        line.append(0x0A)
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }
}
