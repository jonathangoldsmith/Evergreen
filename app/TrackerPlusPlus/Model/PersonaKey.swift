import Foundation

enum PersonaKey: String, Codable, CaseIterable, Identifiable {
    case sam, alex, jordan

    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}
