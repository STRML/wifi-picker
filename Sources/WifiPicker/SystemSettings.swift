import AppKit

enum SystemSettings {
    static func openLocationPrivacy() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
    }

    static func openWiFi() {
        open("x-apple.systempreferences:com.apple.wifi-settings-extension")
    }

    private static func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}
