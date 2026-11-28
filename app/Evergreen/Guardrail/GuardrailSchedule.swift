import Foundation

/// Which guardrail notifications go out, and when (plan item 7, design
/// decision 10, eng re-run R9). A pure function so the budget has table tests.
///
/// - Spike notes fire at 7 PM the evening before a run that starts before
///   noon, otherwise at 7 AM on the day.
/// - The morning check fires per `MorningCheckTiming`; none once a run is decided.
/// - A bedtime note (`Bedtime`) fires an hour before lights out, the evening
///   before a long or hard morning run. Its urgency is a note's, so it's the
///   first dropped.
/// - At most 2 a day, counted by the day a note fires. Sunday's pain note is
///   never dropped: an evening swap note competing with it is folded into its
///   text, and otherwise the least urgent note by `TodayUrgency` is dropped
///   (morning checks before swap notes, later before earlier). Dropped notes still show as
///   Today cards.
enum GuardrailSchedule {
    static let perDay = 2
    static let swapEveningHour = 19
    static let swapMorningHour = 7

    struct RunState {
        var run: PlannedRun
        /// The flag from history alone (no morning answer yet), if any.
        var flag: GuardrailFlag?
        /// A swap or keep was ever chosen for this run.
        var decided: Bool
        var checkedIn: Bool
    }

    static func notes(runs: [RunState], painWeeks: [Date], bedtimes: [Bedtime] = [], now: Date,
                      calendar: Calendar) -> [GuardrailNote] {
        var notes: [GuardrailNote] = []
        for state in runs where !state.decided && state.run.start > now {
            if let flag = state.flag {
                let at = swapTime(for: state.run, calendar: calendar)
                if at > now {
                    let copy = GuardrailCopy.spikeNote(state.run, flag, now: at, calendar: calendar)
                    notes.append(GuardrailNote(kind: .swap, fireAt: at, title: copy.title, body: copy.body,
                                               run: state.run, flag: flag))
                }
            }
            // One morning check a day, for the day's first run (design decision 7).
            if state.run.size != nil, !state.checkedIn, isFirstSizedRun(state.run, in: runs, calendar: calendar) {
                let at = MorningCheckTiming.asks(for: state.run, calendar: calendar)
                if at > now {
                    notes.append(GuardrailNote(kind: .morningCheck, fireAt: at, title: GuardrailCopy.morningCheck.title,
                                               body: GuardrailCopy.morningCheck.body, run: state.run))
                }
            }
        }
        for bedtime in bedtimes where bedtime.fireAt > now && bedtime.run.start > now {
            let copy = bedtime.note(calendar: calendar)
            notes.append(GuardrailNote(kind: .bedtime, fireAt: bedtime.fireAt, title: copy.title, body: copy.body,
                                       run: bedtime.run))
        }
        for week in painWeeks {
            let at = PainWeek.asksAt(week, calendar: calendar)
            if at > now {
                notes.append(GuardrailNote(kind: .pain, fireAt: at, title: "Evergreen", body: painBody,
                                           weekStart: week))
            }
        }
        return budget(notes, calendar: calendar).sorted { $0.fireAt < $1.fireAt }
    }

    static let painBody = "How was your week? Any pain?"

    static func swapTime(for run: PlannedRun, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: run.start)
        if calendar.component(.hour, from: run.start) < 12 {
            let evening = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            return calendar.date(bySettingHour: swapEveningHour, minute: 0, second: 0, of: evening) ?? evening
        }
        return calendar.date(bySettingHour: swapMorningHour, minute: 0, second: 0, of: day) ?? day
    }

    /// Applies the 2-a-day limit per firing day.
    static func budget(_ notes: [GuardrailNote], calendar: Calendar) -> [GuardrailNote] {
        let byDay = Dictionary(grouping: notes) { calendar.startOfDay(for: $0.fireAt) }
        return byDay.values.flatMap { day -> [GuardrailNote] in
            var kept = day
            guard kept.count > perDay else { return kept }
            // Fold an evening swap note into the Sunday pain note.
            if let painIndex = kept.firstIndex(where: { $0.kind == .pain }),
               let swapIndex = kept.firstIndex(where: { $0.kind == .swap && $0.fireAt >= kept[painIndex].fireAt }) {
                let swap = kept[swapIndex].body
                kept[painIndex].body += " Also: \(swap.prefix(1).lowercased())\(swap.dropFirst())"
                kept[painIndex].run = kept[swapIndex].run
                kept[painIndex].flag = kept[swapIndex].flag
                kept.remove(at: swapIndex)
            }
            while kept.count > perDay {
                let droppable = kept.indices.filter { kept[$0].kind != .pain }
                guard let drop = droppable.max(by: { rank(kept[$0]) < rank(kept[$1]) }) else { break }
                kept.remove(at: drop)
            }
            return kept
        }
    }

    /// Higher drops first, by the shared urgency order (morning checks before
    /// swap notes), later before earlier.
    private static func rank(_ note: GuardrailNote) -> (TodayUrgency, Date) {
        (note.kind.urgency, note.fireAt)
    }

    static func isFirstSizedRun(_ run: PlannedRun, in runs: [RunState], calendar: Calendar) -> Bool {
        let sameDay = runs.map(\.run).filter { $0.size != nil && calendar.isDate($0.start, inSameDayAs: run.start) }
        return sameDay.min { $0.start < $1.start }?.key == run.key
    }
}
