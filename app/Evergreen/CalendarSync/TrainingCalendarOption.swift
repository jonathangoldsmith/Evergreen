import Foundation

/// A calendar the person can mark as holding their training plan.
struct TrainingCalendarOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// The account it's on ("iCloud", "Gmail"), to tell same-named calendars apart.
    let source: String
    /// Pre-selected because its name looks like a training plan.
    let suggested: Bool

    static let trainingNames = ["runna", "trainingpeaks", "training peaks", "final surge", "finalsurge", "training"]

    static func looksLikeTraining(_ title: String) -> Bool {
        let lower = title.lowercased()
        return trainingNames.contains { lower.contains($0) }
    }
}
