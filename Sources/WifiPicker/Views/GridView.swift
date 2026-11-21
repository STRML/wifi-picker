import SwiftUI
import WifiPickerCore

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

struct GridView: View {
    let model: PickerModel
    private static let space = "grid"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: Metrics.columnSpacing) {
                    ForEach(model.layout.columns, id: \.kind.rawValue) { column in
                        columnView(column)
                    }
                }
                .padding(.horizontal, Metrics.gridInset)
                .padding(.vertical, Metrics.gridVerticalInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .coordinateSpace(.named(Self.space))
            }
            .onChange(of: model.focusedSSID) { _, ssid in
                guard let ssid else { return }
                proxy.scrollTo(ssid)
            }
            .onPreferenceChange(CellFramesKey.self) { model.cellFramesChanged($0) }
        }
    }

    private func columnView(_ column: LayoutColumn) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ColumnHeader(kind: column.kind)
            if column.slots.isEmpty {
                Placeholder()
            }
            ForEach(column.slots, id: \.self) { ssid in
                slot(ssid, in: column.kind)
                    .frame(height: Metrics.rowPitch, alignment: .top)
            }
        }
        .frame(width: Metrics.cellWidth, alignment: .top)
    }

    @ViewBuilder
    private func slot(_ ssid: String, in column: ColumnKind) -> some View {
        if let cell = model.cell(for: ssid) {
            CellView(
                ssid: ssid,
                column: column,
                cell: cell,
                isCurrent: model.interface.ssid == ssid,
                isFocused: model.focusedSSID == ssid,
                isJoining: model.joiningSSID == ssid,
                space: Self.space,
                activate: { model.activate(ssid) }
            )
        } else {
            Color.clear.frame(width: Metrics.cellWidth, height: Metrics.cellHeight)
        }
    }
}

private struct Placeholder: View {
    var body: some View {
        Text("None nearby")
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .padding(.leading, 8)
            .frame(width: Metrics.cellWidth, height: Metrics.cellHeight, alignment: .leading)
            .frame(height: Metrics.rowPitch, alignment: .top)
    }
}

private struct ColumnHeader: View {
    let kind: ColumnKind

    var body: some View {
        Label(title, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.leading, 8)
            .padding(.bottom, 4)
            .frame(width: Metrics.cellWidth, alignment: .bottomLeading)
            .frame(height: Metrics.columnHeaderHeight)
    }

    private var title: String {
        switch kind {
        case .hotspots: "Hotspots"
        case .known: "Known"
        case .other: "Other"
        }
    }

    private var symbol: String {
        switch kind {
        case .hotspots: "personalhotspot"
        case .known: "star.fill"
        case .other: "wifi"
        }
    }
}
