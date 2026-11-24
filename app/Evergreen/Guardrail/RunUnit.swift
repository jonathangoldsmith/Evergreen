import Foundation

/// How a planned run is measured: by distance when its title gives one,
/// otherwise by time (plan item 3). The swap card speaks in the plan's unit.
enum RunUnit: String, Codable, Hashable, Sendable {
    case km
    case minutes
}
