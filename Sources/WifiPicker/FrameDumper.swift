import CoreGraphics
import Foundation
import SwiftUI

struct CellFrames: Equatable {
    let column: String
    let window: CGRect
    let grid: CGRect
}

struct CellFramesKey: PreferenceKey {
    static let defaultValue: [String: CellFrames] = [:]

    static func reduce(value: inout [String: CellFrames], nextValue: () -> [String: CellFrames]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct CaptureCellFramesKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var captureCellFrames: Bool {
        get { self[CaptureCellFramesKey.self] }
        set { self[CaptureCellFramesKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func captureCellFrames(using dumper: FrameDumper?) -> some View {
        if let dumper {
            self
                .environment(\.captureCellFrames, true)
                .onPreferenceChange(CellFramesKey.self) { dumper.update($0) }
        } else {
            self
        }
    }
}

@MainActor
final class FrameDumper {
    private struct Cell: Encodable {
        let ssid: String
        let column: String
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
    private var latestFrames: [String: CellFrames] = [:]

    init(path: String) {
        url = URL(fileURLWithPath: path)
        encoder.outputFormatting = [.sortedKeys]
        FileManager.default.createFile(atPath: path, contents: nil)
    }

    func update(_ frames: [String: CellFrames]) {
        latestFrames = frames
        write(reason: "layout", frames: frames)
    }

    func scanFinished() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self else { return }
            write(reason: "scan-finished", frames: latestFrames)
        }
    }

    private func write(reason: String, frames: [String: CellFrames]) {
        let cells = frames
            .map {
                Cell(
                    ssid: $0.key,
                    column: $0.value.column,
                    x: $0.value.window.minX,
                    y: $0.value.window.minY,
                    width: $0.value.window.width,
                    height: $0.value.window.height,
                    gridX: $0.value.grid.minX,
                    gridY: $0.value.grid.minY
                )
            }
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
