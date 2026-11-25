import Foundation
import Testing
@testable import Evergreen

/// The return-to-running plan's shape (range plan item 21, design decision 19).
struct ReturnPlanTests {
    static let cal = Fixture.calendar

    @Test func sessionsGrowAtMostTenPercentAWeekAndStayUnderTheReturnLimit() {
        let lengths = ReturnPlan.minutesByWeek
        #expect(lengths == [20, 22, 24, 26])
        for (before, after) in zip(lengths, lengths.dropFirst()) {
            #expect(Double(after) <= Double(before) * 1.1)
        }
        #expect(lengths.allSatisfy { $0 < ReturnPlan.limitMinutes })
    }

    @Test func fourWeeksOnThePickedDaysAtThePickedTime() throws {
        // From Thursday the 19th at noon: Mon/Wed/Sat at 7 AM.
        let sessions = ReturnPlan.sessions(from: Fixture.at(12), weekdays: [2, 4, 7], startMinute: 7 * 60, calendar: Self.cal)
        #expect(sessions.count == 12)
        let first = try #require(sessions.first)
        #expect(Self.cal.component(.weekday, from: first.start) == 7)       // Saturday, not this morning
        #expect(Self.cal.component(.hour, from: first.start) == 7)
        #expect(first.title == "Walk-run 20 min: 1 min run, 2 min walk")
        #expect(sessions.last?.minutes == 26 && sessions.last?.runMinutes == 4)
        #expect(Set(sessions.map(\.week)) == [0, 1, 2, 3])
    }

    @Test func resumingPicksUpAtThePausedWeek() {
        let sessions = ReturnPlan.sessions(from: Fixture.at(12), weekdays: [2, 4, 7], startMinute: 7 * 60, fromWeek: 2,
                                           calendar: Self.cal)
        #expect(sessions.count == 6)
        #expect(sessions.first?.minutes == 24 && sessions.first?.week == 2)
    }

    @Test func noDaysMeansNoSessions() {
        #expect(ReturnPlan.sessions(from: Fixture.at(12), weekdays: [], startMinute: 420, calendar: Self.cal).isEmpty)
    }

    @Test func withoutRecentRunsTheDaysAreMondayWednesdaySaturdayAt7() {
        let suggested = ReturnPlan.suggestedDays(history: [], today: Fixture.at(12), calendar: Self.cal)
        #expect(suggested.weekdays == [2, 4, 7] && suggested.startMinute == 420)
    }

    @Test func withRecentRunsTheDaysAreTheUsualOnes() {
        let history = HistoryPlanTests.month.map { w in
            Workout(id: w.id, activityType: w.activityType, start: w.start, end: w.end, effort: nil, avgHeartRate: nil,
                    source: .health, distanceKm: w.distanceKm)
        }
        let suggested = ReturnPlan.suggestedDays(history: history, today: HistoryPlanTests.storyDay, calendar: HistoryPlanTests.cal)
        #expect(suggested.weekdays == [1, 3])                                // Sunday and Tuesday runs
    }
}
