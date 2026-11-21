import SwiftUI
import WifiPickerCore

struct PickerRootView: View {
    let model: PickerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.title).font(.headline)
            Text(model.statusLine).foregroundStyle(.secondary)
            ForEach(model.layout.readingOrder, id: \.self) { ssid in
                Text(ssid).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }
}
