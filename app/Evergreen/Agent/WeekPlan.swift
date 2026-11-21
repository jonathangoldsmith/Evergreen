import Foundation

/// The harness planner's answer from `POST /workouts/recommend`: the next 7
/// days as calendar-ready sessions, optional extras, and how it was made.
/// Only what the app shows is decoded; other keys (signals, condition,
/// auditId, rules) are ignored.
struct WeekPlan: Decodable, Sendable {
    /// One planned day: an `addWorkout` with a slot, or a `note` (race day).
    struct Session: Decodable, Identifiable, Sendable {
        var id: String
        var kind: String
        var title: String
        var after: Slot?
        var reason: String
        var evidence: [Citation]?
    }

    /// A web source behind a session's rule or a suggestion.
    struct Citation: Decodable, Hashable, Sendable {
        var source: String
        var passage: String?
        var url: String?

        var link: URL? { url.flatMap(URL.init(string:)) }
    }

    /// An optional extra from expert guidance. Never booked.
    struct Suggestion: Decodable, Identifiable, Sendable {
        struct Source: Decodable, Hashable, Sendable {
            var title: String?
            var host: String?
            var url: String?

            var link: URL? { url.flatMap(URL.init(string:)) }
        }

        var id: String
        var title: String
        var minutes: Int?
        var when: String?
        var why: String?
        var source: Source?
    }

    /// "Your last 7 days carried 0.74× your usual training load, …"
    var summary: String?
    var actions: [Session]
    var suggestions: [Suggestion]?
    /// "sie" when Superlinked SIE wrote the reasons, "rules" for the templates.
    var source: String?
    /// "phone" when it planned from this phone's memory, "bundled" for the harness's copy.
    var memorySource: String?

    /// Sessions in time order; notes (no slot) sort last.
    var sessions: [Session] {
        actions.sorted { ($0.after?.start ?? .distantFuture) < ($1.after?.start ?? .distantFuture) }
    }
}
