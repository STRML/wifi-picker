import SwiftUI

// The system switch renders grey whenever the app is inactive, which a
// non-activating panel always is on first open. This draws the active look.
struct AccentSwitchStyle: ToggleStyle {
    private let size = CGSize(width: 38, height: 22)
    private let inset: CGFloat = 2

    func makeBody(configuration: Configuration) -> some View {
        let knob = size.height - 2 * inset
        let travel = size.width - knob - 2 * inset
        return Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(configuration.isOn ? Color.accentColor : Color.primary.opacity(0.18))
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .frame(width: knob, height: knob)
                    .offset(x: inset + (configuration.isOn ? travel : 0))
            }
            .frame(width: size.width, height: size.height)
            .animation(.easeOut(duration: 0.15), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
