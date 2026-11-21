import SwiftUI

struct StatsRow: View {
    let stats: LinkStats?

    var body: some View {
        HStack(spacing: 6) {
            if let stats {
                Chip(symbol: "cellularbars", text: "\(stats.rssi) dBm", tint: SignalQuality(rssi: stats.rssi).color)
                Chip(symbol: "waveform", text: "SNR \(stats.snr) dB")
                Chip(symbol: "dot.radiowaves.left.and.right", text: channelText(stats))
                Chip(symbol: "speedometer", text: rateText(stats))
                if let ipv4 = stats.ipv4 {
                    Chip(symbol: "network", text: stats.router.map { "\(ipv4) → \($0)" } ?? ipv4)
                }
            } else {
                Text("Not connected")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 20)
        .lineLimit(1)
    }

    private func channelText(_ stats: LinkStats) -> String {
        [stats.channel.map { "Ch \($0)" }, stats.band, stats.width].compactMap { $0 }.joined(separator: " · ")
    }

    private func rateText(_ stats: LinkStats) -> String {
        let rate = "\(Int(stats.txRate.rounded())) Mbps"
        return stats.standard.map { "\($0) · \(rate)" } ?? rate
    }
}

private struct Chip: View {
    let symbol: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Capsule().fill(.quaternary.opacity(0.6)))
        .fixedSize()
    }
}

private enum SignalQuality {
    case strong, fair, weak

    init(rssi: Int) {
        self = rssi >= -60 ? .strong : rssi >= -72 ? .fair : .weak
    }

    var color: Color {
        switch self {
        case .strong: .green
        case .fair: .yellow
        case .weak: .orange
        }
    }
}
