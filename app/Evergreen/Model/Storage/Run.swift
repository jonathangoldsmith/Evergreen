import Foundation
import SwiftData

// The phone's memory. The harness stores nothing between calls (eng review D3),
// so everything it needs to see again lives here. The contract structs stay the
// wire format; these models map to and from them.

/// The one demo run on this phone: who it's about and today's story. A new day
/// clears the run but keeps the person and onboarding (eng review D6).
@Model
final class Run {
    var persona: String
    var onboarded: Bool
    var storyDay: Date
    /// Demo clock as minutes after midnight on the story day; nil means real time.
    var clockMinutes: Int?
    /// Plan items whose Done sheet has already shown, one id per line. A plain
    /// string on purpose: SwiftData keeps a `[String]` as an archived blob, and
    /// decoding that blob during a save crashed the app after a day rollover.
    var seenCompletionIds: String = ""
    /// The last good `/tick` answer exactly as it arrived, kept on screen when
    /// the agent can't be reached.
    var lastResponse: Data?
    /// Purchases the person approved, one id per line (see seenCompletionIds).
    var approvedPurchaseText: String = ""
    /// The demo controls' conditions and gym visits, JSON-encoded.
    var demoData: Data?
    var visitsData: Data?
    /// When this run's plan was made. A real person's week leaves out today's
    /// usual workouts that had already started by then, so a plan made mid-day
    /// doesn't open with a miss.
    var planMadeAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ActionRecord.run)
    var actions: [ActionRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \LoggedWorkout.run)
    var workouts: [LoggedWorkout] = []

    init(persona: PersonaKey, storyDay: Date) {
        self.persona = persona.rawValue
        self.onboarded = false
        self.storyDay = storyDay
        self.clockMinutes = nil
        self.seenCompletionIds = ""
        self.lastResponse = nil
    }

    var personaKey: PersonaKey { PersonaKey(rawValue: persona) ?? .jordan }

    var approvedPurchaseIds: [String] {
        get { approvedPurchaseText.split(separator: "\n").map(String.init) }
        set { approvedPurchaseText = newValue.joined(separator: "\n") }
    }

    var demo: DemoConditions? {
        get { demoData.flatMap { try? JSONDecoder.contract.decode(DemoConditions.self, from: $0) } }
        set { demoData = newValue.flatMap { try? JSONEncoder.contract.encode($0) } }
    }

    var visits: [Visit] {
        get { visitsData.flatMap { try? JSONDecoder.contract.decode([Visit].self, from: $0) } ?? [] }
        set { visitsData = newValue.isEmpty ? nil : try? JSONEncoder.contract.encode(newValue) }
    }

    var seenCompletions: [String] {
        get { seenCompletionIds.split(separator: "\n").map(String.init) }
        set { seenCompletionIds = newValue.joined(separator: "\n") }
    }
}
