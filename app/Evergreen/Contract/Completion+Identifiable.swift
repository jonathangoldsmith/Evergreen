import Foundation

/// A completion is shown once, as the Done sheet, keyed by its plan item.
extension Completion: Identifiable {
    var id: String { planItemId }
}
