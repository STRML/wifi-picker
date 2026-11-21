import AppKit
import SwiftUI

struct FooterView: View {
    var body: some View {
        HStack(spacing: 4) {
            MenuRowButton(title: "Wi-Fi Settings…") {
                SystemSettings.openWiFi()
            }
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(MenuRowStyle())
            .foregroundStyle(.secondary)
            .help("Quit Wi-Fi Picker")
            .accessibilityLabel("Quit Wi-Fi Picker")
        }
        .padding(.horizontal, 6)
    }
}

private struct MenuRowButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowStyle())
    }
}

private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRowBody(configuration: configuration)
    }
}

private struct MenuRowBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var hovering = false

    var body: some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .opacity(configuration.isPressed ? 1 : hovering ? 0.8 : 0)
            }
            .onHover { hovering = $0 }
            .focusEffectDisabled()
    }
}
