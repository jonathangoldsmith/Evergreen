import Foundation
import Testing
@testable import Evergreen

/// The brake's rule (plan items 5 and 6): spikes against the 30-day longest,
/// the injury window, Sore and Tired, floors and rounding. Every case is a
/// plain value in, a flag (or none) out.
struct GuardrailRuleTests {
    static let cal = Fixture.calendar
    /// Sunday 22 November 2026, 8 AM: the long run.
    static let sunday = Fixture.at(8, dayOffset: 3)

    static func run(_ size: RunSize?, title: String = "Long run", at start: Date = sunday,
                    minutes: Double = 90, hard: Bool = false) -> PlannedRun {
        PlannedRun(key: "cal|\(start)|\(title)", title: title, calendarTitle: "Runna", start: start,
                   end: start.addingTimeInterval(minutes * 60), size: size, isHard: hard, isAllDay: false)
    }

    /// A completed run `daysBack` days before Sunday.
    static func done(_ daysBack: Int, km: Double? = nil, minutes: Double = 60, type: String = "Running") -> Workout {
        let start = cal.date(byAdding: .day, value: -daysBack, to: sunday)!
        return Workout(id: "w\(daysBack)-\(km ?? minutes)", activityType: type, start: start,
                       end: start.addingTimeInterval(minutes * 60), effort: nil, avgHeartRate: nil,
                       source: .health, distanceKm: km)
    }

    static func context(_ history: [Workout], injury: Date? = nil, check: MorningCheck? = nil,
                        upcoming: [PlannedRun] = []) -> GuardrailRule.Context {
        .init(history: history, injuryMonth: injury, check: check, upcoming: upcoming, calendar: cal)
    }

    /// Longest 13 km in the last month, plus shorter runs.
    static let month = [done(4, km: 8), done(8, km: 13), done(15, km: 10), done(22, km: 12)]

    // MARK: Spike

    @Test func eighteenAfterThirteenIsASpikeCappedAtTheLongest() throws {
        let flag = try #require(GuardrailRule.flag(for: Self.run(.km(18)), Self.context(Self.month)))
        #expect(flag.kind == .spike)
        #expect(flag.suggested == .km(13))
        #expect(flag.longest30 == .km(13))
        #expect(flag.jumpPercent == 38)
        #expect(!flag.injuryAdjusted)
    }

    @Test func withinTenPercentIsNotFlagged() {
        #expect(GuardrailRule.flag(for: Self.run(.km(14.3)), Self.context(Self.month)) == nil)
        #expect(GuardrailRule.flag(for: Self.run(.km(14.4)), Self.context(Self.month))?.kind == .spike)
    }

    @Test func afterAnInjuryFivePercentFlagsAndTheCapDropsTenPercent() throws {
        let august = Self.cal.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let flag = try #require(GuardrailRule.flag(for: Self.run(.km(14)), Self.context(Self.month, injury: august)))
        #expect(flag.kind == .spike && flag.injuryAdjusted)
        #expect(flag.suggested == .km(11))          // 13 × 0.9 = 11.7, rounded down
    }

    @Test func anInjuryOverTwelveMonthsAgoDoesNotTightenTheRule() {
        let longAgo = Self.cal.date(from: DateComponents(year: 2025, month: 10, day: 1))!
        #expect(GuardrailRule.flag(for: Self.run(.km(14)), Self.context(Self.month, injury: longAgo)) == nil)
    }

    @Test func runsOutsideThirtyDaysAndOtherActivitiesDoNotCount() throws {
        let history = [Self.done(4, km: 8), Self.done(9, km: 9), Self.done(31, km: 20), Self.done(5, km: 25, type: "Cycling")]
        let flag = try #require(GuardrailRule.flag(for: Self.run(.km(12)), Self.context(history)))
        #expect(flag.longest30 == .km(9))
    }

    @Test func aDurationPlanComparesDurations() throws {
        let history = [Self.done(3, minutes: 40), Self.done(10, minutes: 50)]
        let flag = try #require(GuardrailRule.flag(for: Self.run(.minutes(75)), Self.context(history)))
        #expect(flag.suggested == .minutes(50) && flag.planned.unit == .minutes)
    }

    @Test func aDistancePlanIgnoresRunsWithoutADistance() {
        // Only one run has a distance, so there aren't 2 comparable runs.
        let history = [Self.done(3, km: 8), Self.done(10, minutes: 50)]
        #expect(GuardrailRule.flag(for: Self.run(.km(18)), Self.context(history)) == nil)
    }

    @Test func theFloorWinsOverTheCap() throws {
        let history = [Self.done(3, km: 2), Self.done(6, km: 1.5)]
        let flag = try #require(GuardrailRule.flag(for: Self.run(.km(3.5)), Self.context(history)))
        #expect(flag.suggested == .km(3))
    }

    @Test func aFloorThatReachesThePlannedSizeMeansNoFlag() {
        let history = [Self.done(3, km: 2), Self.done(6, km: 1.5)]
        #expect(GuardrailRule.flag(for: Self.run(.km(3)), Self.context(history)) == nil)
    }

    // MARK: No recent runs

    @Test func withoutTwoRecentRunsThereIsNoSpike() {
        #expect(GuardrailRule.flag(for: Self.run(.km(18)), Self.context([Self.done(3, km: 5)])) == nil)
    }

    @Test func afterAnInjuryWithNoRecentRunsALongRunIsAReturnSpike() throws {
        let september = Self.cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let flag = try #require(GuardrailRule.flag(for: Self.run(.minutes(45)), Self.context([], injury: september)))
        #expect(flag.kind == .returnSpike && flag.suggested == .minutes(30))
        #expect(GuardrailRule.flag(for: Self.run(.minutes(30)), Self.context([], injury: september)) == nil)
        #expect(GuardrailRule.flag(for: Self.run(.km(8)), Self.context([], injury: september))?.suggested == .km(5))
    }

    // MARK: Sore and Tired

    @Test func soreCutsALongRunByThirtyPercent() throws {
        let flag = try #require(GuardrailRule.flag(for: Self.run(.km(10)), Self.context(Self.month, check: .sore)))
        #expect(flag.kind == .sore && flag.suggested == .km(7))
    }

    @Test func soreOnAShortRunIsNotFlagged() {
        #expect(GuardrailRule.flag(for: Self.run(.km(6), minutes: 35), Self.context(Self.month, check: .sore)) == nil)
    }

    @Test func tiredCutsAHardRunByTwentyPercent() throws {
        let tempo = Self.run(.minutes(45), title: "Tempo 45 min", minutes: 45, hard: true)
        let history = [Self.done(3, minutes: 50), Self.done(8, minutes: 55)]
        let flag = try #require(GuardrailRule.flag(for: tempo, Self.context(history, check: .tired)))
        #expect(flag.kind == .tired && flag.suggested == .minutes(35))
    }

    @Test func tiredOnAnEasyShortRunIsNotFlagged() {
        let easy = Self.run(.minutes(40), title: "Easy 40 min", minutes: 40)
        #expect(GuardrailRule.flag(for: easy, Self.context(Self.month, check: .tired)) == nil)
    }

    @Test func freshNeverFlagsByItself() {
        #expect(GuardrailRule.flag(for: Self.run(.km(12)), Self.context(Self.month, check: .fresh)) == nil)
    }

    @Test func aCutUnderTenPercentBecomesRunItEasy() throws {
        // 25 min × 0.8 = 20, the floor; still a 20% cut. 22 min × 0.8 = 17.6 → 15 → floor 20: a 9% cut.
        let short = Self.run(.minutes(22), title: "Threshold 22 min", minutes: 22, hard: true)
        let flag = try #require(GuardrailRule.flag(for: short, Self.context([], check: .tired)))
        #expect(flag.keepEasy && flag.suggested == .minutes(22))
    }

    @Test func theLongestPlannedRunOfTheWeekCountsAsLong() throws {
        let saturday = Self.run(.km(8), title: "Run 8 km", at: Fixture.at(8, dayOffset: 2), minutes: 45)
        let tuesday = Self.run(.km(6), title: "Run 6 km", at: Fixture.at(8, dayOffset: 5), minutes: 35)
        let flag = try #require(GuardrailRule.flag(for: saturday, Self.context([], check: .sore, upcoming: [saturday, tuesday])))
        #expect(flag.kind == .sore && flag.suggested == .km(5))
    }

    @Test func soreAndASpikeTogetherGiveTheSmallerSuggestion() throws {
        // Spike suggests 13; Sore suggests 18 × 0.7 = 12.6 → 12.
        let flag = try #require(GuardrailRule.flag(for: Self.run(.km(18)), Self.context(Self.month, check: .sore)))
        #expect(flag.kind == .sore && flag.suggested == .km(12))
    }

    @Test func anAllDayRunWithoutASizeIsNeverFlagged() {
        #expect(GuardrailRule.flag(for: Self.run(nil), Self.context(Self.month, check: .sore)) == nil)
    }
}
