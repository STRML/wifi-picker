import SwiftUI
import WifiPickerCore

struct CellFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct GridView: View {
    let model: PickerModel
    private static let space = "grid"

    var body: some View {
        let rows = model.layout.rows(columns: Metrics.columns)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        if row.startsSection {
                            SectionHeader(kind: row.section)
                        }
                        HStack(alignment: .top, spacing: Metrics.columnSpacing) {
                            ForEach(row.slots, id: \.self) { ssid in
                                slot(ssid)
                            }
                        }
                        .frame(height: Metrics.rowPitch, alignment: .top)
                    }
                }
                .padding(.horizontal, Metrics.gridInset)
                .padding(.vertical, Metrics.gridVerticalInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .coordinateSpace(.named(Self.space))
            }
            .overlay { placeholder(isEmpty: rows.isEmpty) }
            .onChange(of: model.focusedSSID) { _, ssid in
                guard let ssid else { return }
                proxy.scrollTo(ssid)
            }
            .onPreferenceChange(CellFramesKey.self) { model.cellFramesChanged($0) }
        }
    }

    @ViewBuilder
    private func slot(_ ssid: String) -> some View {
        if let cell = model.cell(for: ssid) {
            CellView(
                ssid: ssid,
                cell: cell,
                isCurrent: model.interface.ssid == ssid,
                isFocused: model.focusedSSID == ssid,
                space: Self.space,
                activate: { model.activate(ssid) }
            )
        } else {
            Color.clear.frame(width: Metrics.cellWidth, height: Metrics.cellHeight)
        }
    }

    @ViewBuilder
    private func placeholder(isEmpty: Bool) -> some View {
        if isEmpty {
            Text(model.scanning ? "Looking for networks…" : "No networks found")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

private struct SectionHeader: View {
    let kind: SectionKind

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .bottomLeading)
            .frame(height: Metrics.sectionHeaderHeight)
    }

    private var title: String {
        switch kind {
        case .known: "Known Networks"
        case .other: "Other Networks"
        case .new: "New"
        }
    }
}
