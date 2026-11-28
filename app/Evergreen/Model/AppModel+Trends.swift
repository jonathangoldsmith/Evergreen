import Foundation

/// Trends as sentences (TODOS item 5): the Trends sheet's lines, from the
/// workouts, the health days and the last 4 weeks' range reports.
extension AppModel {
    var trends: Trends {
        Trends.make(workouts: workouts, days: healthDays, range: lastFourWeeksRange, on: now, calendar: calendar)
    }

    /// The range reports of this week and the 3 before, summed.
    var lastFourWeeksRange: Trends.Range {
        let thisWeek = PainWeek.monday(of: now, calendar: calendar)
        return (0..<4).reduce(Trends.Range(daysInRange: 0, daysCounted: 0, swaps: 0)) { total, back in
            guard let week = calendar.date(byAdding: .day, value: -7 * back, to: thisWeek) else { return total }
            let report = rangeReport(for: week)
            return Trends.Range(daysInRange: total.daysInRange + report.daysInRange,
                                daysCounted: total.daysCounted + report.daysCounted, swaps: total.swaps + report.swaps)
        }
    }

    /// Demo beat: Jordan's trends, with a month of mornings where the last
    /// week's resting heart rate is 3 below his usual, sleep 25 minutes under
    /// and heart rate variability a little up. Opens the Trends sheet.
    func showTrendsDemo() {
        resetDemo()
        demoHealthDays = Self.trendDays(storyDay: storyDay, calendar: calendar)
        showsTrends = true
    }

    /// 60 days: resting heart rate about 49, sleep about 7h 30 and HRV about
    /// 62 ms, then the last 7 days at 46, 7h 05 and 66.
    static func trendDays(storyDay: Date, calendar: Calendar) -> [HealthHistory.Day] {
        let today = calendar.startOfDay(for: storyDay)
        return (1...Trends.hrvUsualDays).reversed().compactMap { back -> HealthHistory.Day? in
            guard let date = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let recent = back <= 7
            let summary = back <= Trends.usualDays
            return HealthHistory.Day(date: date,
                                     sleepMin: summary ? Double((recent ? 415 : 440) + back % 3 * 10) : nil,
                                     restingHeartRate: summary ? Double((recent ? 45 : 48) + back % 3) : nil,
                                     hrv: Double((recent ? 62 : 58) + back % 9))
        }
    }
}
