import SwiftUI
import WifiPickerCore

struct HeaderView: View {
    let model: PickerModel

    var body: some View {
        HStack(spacing: 10) {
            statusGlyph
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                StatusLine(model: model)
            }
            Spacer(minLength: 8)
            RescanButton(model: model)
            Toggle("Wi-Fi", isOn: powerBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
    }

    private var statusGlyph: some View {
        let connected = model.interface.powerOn && model.interface.ssid != nil
        return ZStack {
            Circle().fill(connected ? Color.accentColor : Color.primary.opacity(0.12))
            Image(systemName: model.interface.powerOn ? "wifi" : "wifi.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(connected ? Color.white : Color.secondary)
        }
        .frame(width: 32, height: 32)
    }

    private var powerBinding: Binding<Bool> {
        Binding(get: { model.interface.powerOn }, set: { model.setPower($0) })
    }
}

private struct StatusLine: View {
    let model: PickerModel

    var body: some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.mini)
                .opacity(model.scanning ? 1 : 0)
                .frame(width: 12, height: 12)
            Text(model.statusLine)
                .font(.system(size: 11))
                .foregroundStyle(model.scanFailed ? Color.red : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(height: 14)
    }
}

private struct RescanButton: View {
    let model: PickerModel

    var body: some View {
        Button {
            model.rescan()
        } label: {
            ZStack {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .opacity(model.scanning ? 0 : 1)
                ProgressView()
                    .controlSize(.small)
                    .opacity(model.scanning ? 1 : 0)
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .focusEffectDisabled()
        .disabled(!model.canScan || model.scanning)
        .keyboardShortcut("r")
        .help("Rescan")
        .accessibilityLabel("Rescan")
    }
}
