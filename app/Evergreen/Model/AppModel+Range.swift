import Foundation

/// The Sunday range report (plan item 18) from what the phone already has:
/// Health workouts, morning answers, app opens and guardrail decisions.
extension AppModel {
    /// The report while it's showing (Sunday 7 PM through Monday), else nil.
    var rangeReport: RangeReport? {
        RangeReport.reportWeek(at: now, painAnswered: { self.painRecord(for: $0) != nil }, calendar: calendar)
            .map(rangeReport(for:))
    }

    func rangeReport(for week: Date) -> RangeReport {
        let end = calendar.date(byAdding: .day, value: 7, to: week) ?? week
        let opened = Set(profile.openedDaysText.split(separator: "\n").map(String.init))
        let days: [RangeReport.Day] = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: week), day <= now else { return nil }
            let counted = workouts.contains { calendar.isDate($0.start, inSameDayAs: day) }
                || checkIns.contains { calendar.isDate($0.createdAt, inSameDayAs: day) }
                || opened.contains(UploadEvent.day(day, calendar: calendar))
            return RangeReport.Day(counted: counted, overSuggestion: ranOverSuggestion(on: day))
        }
        let swaps = decisions.filter { $0.inEffect && $0.choice == .accept && $0.runStart >= week && $0.runStart < end }
        return RangeReport(days: days, swaps: swaps.count,
                           longRunSwap: swaps.count == 1 && swaps[0].runTitle.lowercased().contains("long"))
    }

    /// Kept the plan on a flagged day and ran more than the suggestion. Only
    /// flags the person answered are known for past days.
    func ranOverSuggestion(on day: Date) -> Bool {
        decisions.contains { decision in
            guard decision.inEffect, decision.choice == .keep, calendar.isDate(decision.runStart, inSameDayAs: day)
            else { return false }
            let runs = workouts.filter { $0.activityType == "Running" && calendar.isDate($0.start, inSameDayAs: day) }
            let total = decision.unit == .km ? runs.compactMap(\.distanceKm).reduce(0, +) : runs.map(\.minutes).reduce(0, +)
            return total > decision.suggestedValue
        }
    }

    /// Remembers today as a day the app was opened (last 14 days kept).
    func noteAppOpened() {
        let today = UploadEvent.day(now, calendar: calendar)
        var days = profile.openedDaysText.split(separator: "\n").map(String.init)
        guard !days.contains(today) else { return }
        days = Array((days + [today]).suffix(14))
        profile.openedDaysText = days.joined(separator: "\n")
        try? context.save()
    }

    /// Sends the report's counts for the coach page, re-sent until Tuesday
    /// night as late workouts land (eng re-run outside voice #2).
    func uploadRangeWeek() {
        let thisWeek = PainWeek.monday(of: now, calendar: calendar)
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek
        let week = RangeReport.reportWeek(at: now, painAnswered: { self.painRecord(for: $0) != nil }, calendar: calendar)
            ?? (now < PainWeek.closesAt(lastWeek, calendar: calendar) ? lastWeek : nil)
        guard let week else { return }
        var event = UploadEvent.rangeWeek(rangeReport(for: week), week: week, at: Date(), calendar: calendar)
        if var last = lastRangeUpload {
            last.at = event.at
            if last == event { return }
        }
        event.at = UploadEvent.stamp(Date(), calendar: calendar)
        lastRangeUpload = event
        upload(event)
    }
}
