import Foundation

/// A run's size in its plan's unit: "18 km" or "45 min".
struct RunSize: Codable, Hashable, Sendable {
    var value: Double
    var unit: RunUnit

    static func km(_ value: Double) -> RunSize { RunSize(value: value, unit: .km) }
    static func minutes(_ value: Double) -> RunSize { RunSize(value: value, unit: .minutes) }

    /// "18 km", "12.5 km", "45 min" (minutes always whole).
    var label: String {
        switch unit {
        case .km:
            let tenths = (value * 10).rounded() / 10
            let number = tenths.rounded() == tenths ? String(Int(tenths)) : String(format: "%.1f", tenths)
            return "\(number) km"
        case .minutes:
            return "\(Int(value.rounded())) min"
        }
    }

    /// Rounded for copy: whole km, or the nearest 5 minutes.
    var rounded: RunSize {
        switch unit {
        case .km: RunSize(value: value.rounded(), unit: .km)
        case .minutes: RunSize(value: (value / 5).rounded() * 5, unit: .minutes)
        }
    }
}
