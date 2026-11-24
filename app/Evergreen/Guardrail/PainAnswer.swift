import Foundation

/// Sunday's one-tap answer: "How was your week? Any pain?" (plan item 17).
enum PainAnswer: String, Codable, Hashable, Sendable, CaseIterable {
    case no
    case aLittle
    case yes
    /// Not answered by Tuesday night: left out of outcome counts.
    case noAnswer

    var label: String {
        switch self {
        case .no: "No"
        case .aLittle: "A little"
        case .yes: "Yes"
        case .noAnswer: "No answer"
        }
    }

    /// "A little" and "Yes" go on to the OSTRC questions (BN1).
    var asksOSTRC: Bool { self == .aLittle || self == .yes }
}
