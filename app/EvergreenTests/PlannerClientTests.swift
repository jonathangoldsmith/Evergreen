import Foundation
import Testing
@testable import Evergreen

/// The harness planner (`POST /workouts/recommend`): what the phone sends and
/// that the planner's answer decodes. No network.
struct PlannerClientTests {
    static var pacific: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }

    static func date(_ day: Int, _ hour: Int = 9, minute: Int = 0) -> Date {
        pacific.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func theShoeBeatSendsWearRaceAndLocalDays() throws {
        let boughtOn = Self.pacific.date(from: DateComponents(year: 2026, month: 10, day: 22))!
        let demo = DemoConditions(shoesBoughtOn: boughtOn, shoesStartMiles: 267, raceDate: Self.date(29, 0))
        let busy = [Busy(start: Self.date(20, 16), end: Self.date(20, 17))]
        let request = PlannerClient.request(persona: "jordan", now: Self.date(20, 18, minute: 45), demo: demo,
                                            newPairArrives: Self.date(23, 0), busy: busy, cal: Self.pacific)

        #expect(request.persona == "jordan")
        #expect(request.now == "2026-11-20T18:45:00-08:00")
        #expect(request.shoes == .init(boughtOn: "2026-10-22", startMiles: 267))
        #expect(request.raceDate == "2026-11-29")
        #expect(request.newPairArrives == "2026-11-23")
        #expect(request.busy == busy)
    }

    @Test func withoutTheShoeBeatItSendsNoShoesOrRace() throws {
        let request = PlannerClient.request(persona: "jordan", now: Self.date(20), demo: nil,
                                            newPairArrives: nil, busy: [], cal: Self.pacific)
        let json = String(decoding: try JSONEncoder.contract.encode(request), as: UTF8.self)

        #expect(request.shoes == nil && request.raceDate == nil && request.newPairArrives == nil)
        #expect(!json.contains("shoes") && !json.contains("raceDate") && !json.contains("newPairArrives"))
        #expect(json.contains("\"busy\":[]"))
    }

    @Test func offWithoutTheHarnessSecret() {
        let defaults = UserDefaults(suiteName: "planner-\(UUID().uuidString)")!
        #expect(PlannerClient.configured(defaults: defaults, bundle: Bundle(url: FileManager.default.temporaryDirectory)!) == nil)
        defaults.set("s3cret", forKey: "harness_secret")
        let client = PlannerClient.configured(defaults: defaults, bundle: Bundle(url: FileManager.default.temporaryDirectory)!)
        #expect(client?.baseURL == RecommendClient.defaultURL)
        #expect(client?.secret == "s3cret")
    }

    /// Trimmed from a live answer for Jordan on 2026-11-20, plus a race-day note.
    static let answer = """
    {"summary": "Your last 7 days carried 0.74× your usual training load, so this week is planned at 1513 (cap 1957). Readiness: normal.",
     "signals": {"loadRatio": 0.74},
     "actions": [
      {"id": "wk-2026-11-23-yoga", "kind": "addWorkout", "title": "Planned a 27-minute yoga", "planItemId": "wk-2026-11-23-yoga",
       "after": {"start": "2026-11-23T12:00:00-08:00", "end": "2026-11-23T12:27:00-08:00", "activityType": "Yoga"},
       "reason": "Your usual Monday session is a 27-minute yoga practice.", "points": 10, "rules": [], "evidence": []},
      {"id": "wk-2026-11-29-race", "kind": "note", "title": "Race day", "reason": "Race day. Rest and fuel."},
      {"id": "wk-2026-11-21-running", "kind": "addWorkout", "title": "Planned a 28-minute run", "planItemId": "wk-2026-11-21-running",
       "after": {"start": "2026-11-21T08:00:00-08:00", "end": "2026-11-21T08:28:00-08:00", "activityType": "Running"},
       "reason": "Your taper for the race in 8 days keeps this run short.", "points": 10, "rules": ["taper: race in 8 days"],
       "evidence": [{"source": "Half Marathon Taper: 2-Week Plan Before Race Day (runnersblueprint.com)",
                     "passage": "Do your last long run. Keep it steady, not heroic.",
                     "url": "https://www.runnersblueprint.com/the-ultimate-guide-to-tapering-for-a-half-marathon-strategies-for-success/"}]}
     ],
     "suggestions": [
      {"id": "idea-light-stretching-and-mobility-work", "title": "Light stretching and mobility work", "kind": "mobility",
       "activityType": "Other", "minutes": 10, "when": "during taper", "attachTo": null,
       "why": "Your race is 9 days out; runbikecalc.com suggests it during taper.",
       "source": {"title": "Taper Week Strategies 2026", "host": "runbikecalc.com", "url": "https://runbikecalc.com/blog/taper-week-complete-guide"},
       "quote": "Light stretching and mobility work", "optional": true}
     ],
     "memorySource": "bundled", "live": true, "source": "sie", "auditId": null}
    """

    @Test func thePlannersAnswerDecodesInTimeOrder() throws {
        let plan = try JSONDecoder.contract.decode(WeekPlan.self, from: Data(Self.answer.utf8))

        #expect(plan.summary?.hasPrefix("Your last 7 days carried 0.74×") == true)
        #expect(plan.sessions.map(\.id) == ["wk-2026-11-21-running", "wk-2026-11-23-yoga", "wk-2026-11-29-race"])
        let run = plan.sessions[0]
        #expect(run.after?.activityType == "Running")
        #expect(run.after?.minutes == 28)
        #expect(run.after?.start == Self.date(21, 8))
        #expect(run.evidence?.first?.link?.host == "www.runnersblueprint.com")
        #expect(plan.sessions[2].after == nil)
        #expect(plan.suggestions?.first?.minutes == 10)
        #expect(plan.suggestions?.first?.source?.link != nil)
        #expect(plan.source == "sie")
        #expect(plan.memorySource == "bundled")
    }
}
