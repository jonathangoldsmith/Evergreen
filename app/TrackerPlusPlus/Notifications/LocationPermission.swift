import CoreLocation

/// When-in-use location, which the gym alerts need. Asked only when someone
/// turns gym alerts on.
@MainActor
final class LocationPermission: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<Bool, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    var isAuthorized: Bool {
        [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
    }

    /// Shows the system prompt the first time; returns whether location is on.
    func request() async -> Bool {
        guard manager.authorizationStatus == .notDetermined else { return isAuthorized }
        return await withCheckedContinuation { continuation in
            waiting = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        Task { @MainActor in
            self.waiting?.resume(returning: self.isAuthorized)
            self.waiting = nil
        }
    }
}
