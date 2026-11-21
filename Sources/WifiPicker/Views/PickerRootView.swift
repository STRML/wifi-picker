import SwiftUI
import WifiPickerCore

struct PickerRootView: View {
    let model: PickerModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: model)
                .frame(height: Metrics.headerHeight)
            Separator()
            GridArea(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if let request = model.passwordRequest {
                        PasswordSheet(model: model, request: request)
                    }
                }
            Separator()
            FooterView()
                .frame(height: Metrics.footerHeight)
        }
        .frame(width: Metrics.panelWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .transaction { $0.animation = nil }
    }
}

struct Separator: View {
    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: Metrics.separatorHeight)
    }
}
