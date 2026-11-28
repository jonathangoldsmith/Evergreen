import Foundation

/// Sleep the agent defends (TODOS item 4): bedtimes before the long and hard
/// morning runs on the training calendars and in Evergreen's own plan, as a
/// Lock Screen note and a line on Today in the evening.
extension AppModel {
    /// The bedtimes for the runs ahead, from the usual night before `day`.
    func bedtimes(before day: Date) -> [Bedtime] {
        let runs = bedtimeRuns
        let usual = Bedtime.usualSleep(healthDays, before: day, calendar: calendar)
        return Bedtime.plan(runs: runs, usualSleep: usual, calendar: calendar)
    }

    /// The runs a bedtime can be for: the training calendars' (not paused for
    /// a return plan) and Evergreen's own planned runs. The plan already leaves
    /// out a day with a training run, so no morning counts twice.
    var bedtimeRuns: [PlannedRun] {
        trainingRuns.filter { !isPausedForReturn($0) }
            + Bedtime.runs(from: plan.filter { completion(for: $0) == nil })
    }

    /// Tonight's bedtime for Today, from 6 PM the evening before the run.
    var tonightsBedtime: Bedtime? {
        bedtimes(before: now).first { $0.shows(at: now, calendar: calendar) }
    }

    /// Demo beat: 8:30 PM the evening before a 7 AM long run of 1h 40. Jordan
    /// usually sleeps about 7h 30, so Today says lights out by 10:30, and the
    /// Lock Screen note comes now instead of at 9:30.
    func showBedtimeDemo() {
        resetDemo()
        demoHealthDays = Array(Self.roughNightDays(storyDay: storyDay, calendar: calendar).dropLast())
        setClockMinutes(20 * 60 + 30)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: storyDay)) ?? storyDay
        let morning = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        let id = calendarSync.addDemoTrainingWeek([("Long run 1h 40", morning, 100)])
        if let id { setTrainingCalendars(profile.trainingCalendarIds.union([id])) } else { save() }
        refreshTrainingRuns()
        if let bedtime = tonightsBedtime {
            Task { await notifier.send(bedtime.note(calendar: calendar), id: "bedtime-demo") }
        }
    }
}
