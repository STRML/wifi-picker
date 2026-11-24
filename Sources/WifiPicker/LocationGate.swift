import CoreLocation
import WifiPickerCore

@MainActor
final class LocationGate: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    nonisolated(unsafe) var onChange: (@Sendable (LocationAccess) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    var access: LocationAccess {
        Self.access(for: manager.authorizationStatus)
    }

    func requestIfNeeded() {
        guard access == .undetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onChange?(Self.access(for: manager.authorizationStatus))
    }

    nonisolated private static func access(for status: CLAuthorizationStatus) -> LocationAccess {
        switch status {
        case .notDetermined: .undetermined
        case .authorizedAlways, .authorized: .granted
        default: .denied
        }
    }
}
