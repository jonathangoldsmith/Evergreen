import Foundation

// Provisional JSON contract between the app and the harness's `POST /tick`.
//
// The phone owns all state and sends a snapshot; the harness owns every rule in
// `decide(snapshot, now)` and returns actions (eng review D3). The harness's
// Python models become the source of truth: once `contract/fixtures/` exists, an
// XCTest decodes every fixture with these types (eng review D10, task T3).
// Dates are ISO 8601 with an offset; all calendar math uses `timeZone`.
//
// These types stay in one file on purpose: it mirrors the harness's Python
// models, so the two sides can be compared in one place.

/// A time window for one workout, before or after an agent action.
struct Slot: Codable, Hashable {
    var start: Date
    var end: Date
    var activityType: String

    var minutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }
}

/// One planned workout: from the week plan, a comeback, or a routine.
struct PlanItem: Codable, Hashable, Identifiable {
    enum Source: String, Codable { case plan, comeback, routine }

    var id: String
    var slot: Slot
    /// Points for finishing it; a comeback carries 2× (Nature 2021 megastudy).
    var points: Int
    var source: Source
}

/// A completed workout: mock history, real HealthKit import, or the demo control.
struct Workout: Codable, Hashable, Identifiable {
    enum Source: String, Codable { case mock, health, demo }

    var id: String
    var activityType: String
    var start: Date
    var end: Date
    /// HealthKit effort score, 1–10 (`workoutEffortScore` or the estimated one).
    var effort: Double?
    var avgHeartRate: Int?
    var source: Source

    var minutes: Double { end.timeIntervalSince(start) / 60 }
}

/// Something the agent did. The harness chooses `id`, and repeat ticks return the
/// same id, so the phone never applies an action twice (outside voice 5).
/// Every action carries the five parts of design D9: verb, before → after,
/// reason, timestamp, and (in the UI) Undo.
struct AgentAction: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case bookComeback, move, shrink, addRoutine, note }

    var id: String
    var kind: Kind
    /// Headline for `note` actions; the other kinds use their verb.
    var title: String?
    /// The plan item this action creates or changes.
    var planItemId: String?
    var before: Slot?
    var after: Slot?
    var reason: String
    var points: Int?
    var createdAt: Date
}

/// A plan item finished by a workout.
struct Completion: Codable, Hashable {
    var planItemId: String
    var workoutId: String
    var points: Int
    var comeback: Bool
}

/// The person's 4-week normal and this month's goal (plan item 1).
struct Normal: Codable, Hashable {
    var perWeek: Double
    var usual4Weeks: Int
    var goal4Weeks: Int
    var weeklyTarget: Int
    /// Under 14 days of history: starter defaults (eng review D8).
    var gettingToKnowYou: Bool
}

struct TickSnapshot: Codable {
    var now: Date
    var timeZone: String
    var persona: String
    var historyStart: Date
    var planCreatedAt: Date
    /// The plan after every applied action, so the harness sees what's booked.
    var plan: [PlanItem]
    var workouts: [Workout]
    /// Actions the phone has applied, oldest first.
    var actions: [AgentAction]
    /// Actions the person undid; the agent must not redo them.
    var undoneActionIds: [String]
}

struct TickResponse: Codable, Hashable {
    /// New actions. The phone ignores ids it already has.
    var actions: [AgentAction]
    var completions: [Completion]
    var pointsTotal: Int
    var weekDone: Int
    var normal: Normal
}

extension JSONEncoder {
    static let contract: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    static let contract: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
