import Foundation

/// Whose week the app shows: you, from Apple Health, or Jordan, the demo
/// runner whose week drives every demo beat.
enum PersonaKey: String, Codable, CaseIterable, Identifiable {
    case jordan
    case me

    var id: String { rawValue }
    var name: String { self == .me ? "You" : rawValue.capitalized }
    /// Read from Apple Health rather than bundled mock files.
    var isReal: Bool { self == .me }
}
