import AppKit
import SwiftUI

struct FooterView: View {
    var body: some View {
        HStack {
            Button("Join a Hidden Network in Settings…") {
                SystemSettings.openWiFi()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .focusEffectDisabled()
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .focusEffectDisabled()
            .help("Quit Wi-Fi Picker")
            .accessibilityLabel("Quit Wi-Fi Picker")
        }
        .padding(.horizontal, 14)
    }
}
