import Foundation

/// The demo's person. Only Jordan now: his week drives every demo beat.
enum PersonaKey: String, Codable, CaseIterable, Identifiable {
    case jordan

    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}
