import CoreLocation

/// The demo gym for arrival and departure alerts. There's no place picker
/// yet, so it's a fixed spot; in the simulator, move there with
/// `xcrun simctl location booted set 37.3349,-122.0090`.
enum Gym {
    static let name = "the gym"
    static let center = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
    static let radius: CLLocationDistance = 150
}
