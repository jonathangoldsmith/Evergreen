import Foundation

/// The morning answer on a run day: "How do your legs feel?" (plan item 7).
enum MorningCheck: String, Codable, Hashable, Sendable, CaseIterable {
    case fresh
    case tired
    case sore

    var label: String {
        switch self {
        case .fresh: "Fresh"
        case .tired: "Tired"
        case .sore: "Sore"
        }
    }
}
