import SwiftUI
import WifiPickerCore

struct GridArea: View {
    let model: PickerModel

    var body: some View {
        switch model.mode {
        case .networks:
            GridView(model: model)
        case .locationNeeded(let access):
            locationState(access)
        case .wifiOff:
            EmptyState(
                symbol: "wifi.slash",
                message: "Wi-Fi is off",
                buttonTitle: "Turn Wi-Fi On",
                action: { model.setPower(true) }
            )
        }
    }

    private func locationState(_ access: LocationAccess) -> some View {
        EmptyState(
            symbol: "location.slash",
            message: "Wi-Fi Picker needs Location access to read network names.",
            buttonTitle: access == .undetermined ? "Allow Location Access" : "Allow in System Settings",
            action: { access == .undetermined ? model.requestLocation() : SystemSettings.openLocationPrivacy() }
        )
    }
}

private struct EmptyState: View {
    let symbol: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(buttonTitle, action: action)
                .controlSize(.regular)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
