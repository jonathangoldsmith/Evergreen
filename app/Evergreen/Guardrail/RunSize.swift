import Foundation

/// A run's size in its plan's unit: "18 km" or "45 min".
struct RunSize: Codable, Hashable, Sendable {
    var value: Double
    var unit: RunUnit

    static func km(_ value: Double) -> RunSize { RunSize(value: value, unit: .km) }
    static func minutes(_ value: Double) -> RunSize { RunSize(value: value, unit: .minutes) }

    /// "18 km", "12.5 km", "45 min".
    var label: String {
        let number = value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        return unit == .km ? "\(number) km" : "\(number) min"
    }

    /// Rounded for copy: whole km, or the nearest 5 minutes.
    var rounded: RunSize {
        switch unit {
        case .km: RunSize(value: value.rounded(), unit: .km)
        case .minutes: RunSize(value: (value / 5).rounded() * 5, unit: .minutes)
        }
    }
}
