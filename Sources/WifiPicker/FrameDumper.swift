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
    }

    private struct Pass: Encodable {
        let pass: Int
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

    func write(_ frames: [String: CGRect]) {
        let cells = frames
            .map { Cell(ssid: $0.key, x: $0.value.minX, y: $0.value.minY, width: $0.value.width, height: $0.value.height) }
            .sorted { ($0.y, $0.x, $0.ssid) < ($1.y, $1.x, $1.ssid) }
        pass += 1
        let record = Pass(pass: pass, time: ISO8601DateFormatter().string(from: Date()), cells: cells)
        guard var line = try? encoder.encode(record), let handle = try? FileHandle(forWritingTo: url) else { return }
        line.append(0x0A)
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }
}
