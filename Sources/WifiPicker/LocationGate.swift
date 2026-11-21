import CoreLocation

enum LocationAccess: Equatable {
    case undetermined
    case granted
    case denied
}

@MainActor
final class LocationGate: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onChange: (@MainActor (LocationAccess) -> Void)?

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
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { onChange?(Self.access(for: status)) }
    }

    private static func access(for status: CLAuthorizationStatus) -> LocationAccess {
        switch status {
        case .notDetermined: .undetermined
        case .authorizedAlways, .authorized: .granted
        default: .denied
        }
    }
}
