import Foundation
import Testing
@testable import Evergreen

/// The Sunday range report's counts and words (plan item 18, design decision 2).
struct RangeReportTests {
    static func days(_ counted: Int, over: Int = 0) -> [RangeReport.Day] {
        (0..<counted).map { RangeReport.Day(counted: true, outOfRange: $0 < over) }
            + Array(repeating: RangeReport.Day(counted: false, outOfRange: false), count: 7 - counted)
    }

    @Test func aWeekWithASwapSaysSo() {
        let report = RangeReport(days: Self.days(6, over: 1), swaps: 1, longRunSwap: true)
        #expect(report.sentence == "In range 5 of 6 days. 1 swap kept your long run in range.")
    }

    @Test func aQuietWeekSaysNothingNeededChanging() {
        #expect(RangeReport(days: Self.days(4), swaps: 0, longRunSwap: false).sentence
                == "In range 4 of 4 days. Nothing needed changing.")
    }

    @Test func daysWithNoSignAreLeftOut() {
        #expect(RangeReport(days: Self.days(0), swaps: 0, longRunSwap: false).sentence == "Not enough data this week.")
        let report = RangeReport(days: Self.days(3, over: 1), swaps: 0, longRunSwap: false)
        #expect(report.daysCounted == 3 && report.daysInRange == 2)
        #expect(report.sentence == "In range 2 of 3 days.")
    }

    @Test func severalSwaps() {
        #expect(RangeReport(days: Self.days(7), swaps: 2, longRunSwap: false).sentence
                == "In range 7 of 7 days. 2 swaps kept your runs in range.")
    }

    @Test func theReportShowsFromSunday7PMThroughMonday() {
        let cal = Fixture.calendar
        let week = PainWeek.monday(of: Fixture.at(12), calendar: cal)     // Monday the 16th
        let never: (Date) -> Bool = { _ in false }
        #expect(RangeReport.reportWeek(at: Fixture.at(18, dayOffset: 3), painAnswered: never, calendar: cal) == nil)
        #expect(RangeReport.reportWeek(at: Fixture.at(18, dayOffset: 3), painAnswered: { _ in true }, calendar: cal) == week)
        #expect(RangeReport.reportWeek(at: Fixture.at(19, dayOffset: 3), painAnswered: never, calendar: cal) == week)
        #expect(RangeReport.reportWeek(at: Fixture.at(22, dayOffset: 4), painAnswered: never, calendar: cal) == week)
        #expect(RangeReport.reportWeek(at: Fixture.at(9, dayOffset: 5), painAnswered: never, calendar: cal) == nil)
    }

    @Test func theReportNeverSaysSafe() {
        for swaps in 0...3 {
            for long in [true, false] {
                #expect(!RangeReport(days: Self.days(5, over: 1), swaps: swaps, longRunSwap: long).sentence.lowercased().contains("safe"))
            }
        }
    }
}
