import SwiftUI
import WifiPickerCore

struct CellView: View {
    let ssid: String
    let column: ColumnKind
    let cell: LayoutCell
    let isCurrent: Bool
    let isFocused: Bool
    let isJoining: Bool
    let space: String
    let activate: () -> Void
    @State private var hovering = false

    private var interactive: Bool { !cell.dimmed }

    var body: some View {
        Button(action: activate) {
            HStack(spacing: 6) {
                Text(ssid)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                glyph("lock.fill", visible: cell.entry.secure, size: 10)
                glyph("checkmark", visible: isCurrent, size: 11, weight: .bold)
                signalSlot
            }
            .padding(.horizontal, 8)
            .frame(width: Metrics.cellWidth, height: Metrics.cellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(CellButtonStyle(isCurrent: isCurrent, isFocused: isFocused, hovering: hovering && interactive))
        .focusEffectDisabled()
        .disabled(!interactive)
        .opacity(cell.dimmed ? 0.4 : 1)
        .onHover { hovering = $0 }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CellFramesKey.self,
                    value: [ssid: CellFrames(column: String(describing: column), window: proxy.frame(in: .global), grid: proxy.frame(in: .named(space)))]
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ssid)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
    }

    private var signalSlot: some View {
        ZStack {
            Image(systemName: "wifi", variableValue: cell.entry.signal)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 13))
                .opacity(isJoining ? 0 : 1)
            ProgressView()
                .controlSize(.mini)
                .opacity(isJoining ? 1 : 0)
        }
        .frame(width: 18, height: 16)
    }

    private func glyph(_ name: String, visible: Bool, size: CGFloat, weight: Font.Weight = .regular) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(.secondary)
            .opacity(visible ? 1 : 0)
            .frame(width: 12, height: 16)
    }

    private var accessibilityValue: String {
        var parts = [cell.entry.secure ? "Secured" : "Open"]
        if isCurrent { parts.append("Connected") }
        if cell.dimmed { parts.append("Out of range") }
        return parts.joined(separator: ", ")
    }
}

private struct CellButtonStyle: ButtonStyle {
    let isCurrent: Bool
    let isFocused: Bool
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(isCurrent ? 0.2 : 0))
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary).opacity(hovering ? 1 : 0)
                    RoundedRectangle(cornerRadius: 6).fill(.tertiary).opacity(configuration.isPressed ? 1 : 0)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(isFocused ? 1 : 0)
            }
    }
}
