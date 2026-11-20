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
    /// Where it happens when the agent changed it ("Demo Gym"); nil means the
    /// plan's usual place. Shown in the app only; the calendar keeps its title.
    var place: String? = nil

    var minutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }
}

/// A time the person is busy on another calendar. Only the times leave the
/// phone, never the event's title or attendees.
struct Busy: Codable, Hashable {
    var start: Date
    var end: Date
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
    enum Kind: String, Codable {
        case bookComeback, move, shrink, addRoutine, note
        /// A purchase or one of its later states, a one-off workout it added
        /// (break-in runs), and what happened after (the shopping beat).
        case purchase, cancelPurchase, purchaseOutcome, addWorkout
    }

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
    /// Every action in one purchase's trail shares this, so the UI folds them.
    var purchaseId: String? = nil
    /// The purchase as of this action: each state change is a new action with a
    /// new id, because the phone ignores ids it already has.
    var purchase: Purchase? = nil
}

/// Something the agent bought or asked to buy, with the trail behind it. No
/// real money moves: every merchant is a demo merchant.
struct Purchase: Codable, Hashable {
    enum Status: String, Codable { case awaitingApproval, bought, cancelled }

    /// The mandate line that allowed or held the purchase.
    struct Rule: Codable, Hashable {
        var id: String
        var text: String
    }

    /// A cited passage the agent used (Senso, live or cached).
    struct Evidence: Codable, Hashable {
        var source: String
        var passage: String
    }

    /// An option the agent weighed; the chosen one comes first.
    struct Option: Codable, Hashable {
        var name: String
        var amountCents: Int
        var arrives: Date?
        var lostBecause: String?
    }

    var id: String
    var item: String
    var merchant: String
    var amountCents: Int
    var status: Status
    var rule: Rule
    var noticed: String
    var evidence: [Evidence]
    var evidenceLive: Bool
    var options: [Option]
    /// The free-cancel deadline for purchases made without asking.
    var cancelBy: Date?
    var outcome: String?
}

/// One line of the person's standing spending rule.
struct Mandate: Codable, Hashable {
    enum Category: String, Codable { case dayPass, any }

    var id: String
    var text: String
    var category: Category
    /// At or under this, in this category, the agent buys without asking.
    var maxAutoCents: Int
}

/// Conditions the demo controls set instead of live weather or mileage.
struct DemoConditions: Codable, Hashable {
    var rainAt: Date?
    var forecastClear = false
    var shoesBoughtOn: Date?
    var shoesStartMiles: Int?
    var raceDate: Date?
}

/// Arriving somewhere, recorded by the "Arrive at the gym" demo control.
struct Visit: Codable, Hashable {
    var place: String
    var at: Date
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
    /// Busy times on the person's other calendars from the story day on, for
    /// slot defense. Empty without calendar access.
    var busy: [Busy]
    var mandate: [Mandate] = []
    /// Purchases the person tapped "Order it" on.
    var approvedPurchaseIds: [String] = []
    var demo: DemoConditions? = nil
    var visits: [Visit] = []
    /// Whether the person has verified their identity (Persona). Until then the
    /// agent buys nothing on its own; every purchase asks first.
    var identityVerified = false
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
