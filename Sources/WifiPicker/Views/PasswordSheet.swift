import SwiftUI
import WifiPickerCore

struct PasswordSheet: View {
    let model: PickerModel
    let request: PasswordRequest
    @State private var password = ""
    @FocusState private var focused: Bool

    private var joining: Bool { model.joiningSSID != nil }

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.black.opacity(0.18))
                .contentShape(Rectangle())
                .onTapGesture {}
            card
        }
        .id(request.ssid)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Password for “\(request.ssid)”")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .disabled(joining)
                .onSubmit(submit)
            HStack(spacing: 8) {
                Text(request.error ?? " ")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .frame(height: 14)
                Spacer()
                Button("Cancel") { model.dismissPasswordRequest() }
                    .disabled(joining)
                joinButton
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator) }
        .padding(12)
        .onAppear { focused = true }
        .onChange(of: request.error) { _, _ in focused = true }
    }

    private var joinButton: some View {
        Button(action: submit) {
            ZStack {
                Text("Join").opacity(joining ? 0 : 1)
                ProgressView().controlSize(.small).opacity(joining ? 1 : 0)
            }
            .frame(width: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(password.isEmpty || joining)
    }

    private func submit() {
        model.submitPassword(password)
    }
}
