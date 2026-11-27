import Foundation

/// The watch (range plan item 19): what the phone sends it, and what a watch
/// tap does. The rule runs on the phone only.
extension AppModel {
    /// Today's state for the watch: the most urgent run on Today (one order for both), and the week in range.
    var watchState: WatchState {
        let report = rangeReport(for: PainWeek.monday(of: now, calendar: calendar))
        let inRange = report.daysCounted > 0 ? "\(report.daysInRange)/\(report.daysCounted)" : "—"
        let spoken = report.daysCounted > 0 ? "\(report.daysInRange) of \(report.daysCounted) days in range"
                                            : "No days counted yet"
        let run = mostUrgentRun.map(watchRun)
        let today = run.map { $0.decided.map { _ in watchTodayLine() } ?? $0.line } ?? watchTodayLine()
        return WatchState(run: run, inRange: inRange, inRangeSpoken: spoken, today: today, tomorrow: watchTomorrowLine(),
                          sentAt: Date())
    }

    private func watchRun(_ run: PlannedRun) -> WatchState.Run {
        let line = "\(run.start.formatted(.dateTime.weekday(.abbreviated))) · \(run.title) at \(run.start.clock)"
        var state = WatchState.Run(key: run.key, line: line, start: run.start, asksCheck: needsMorningCheck(run))
        if let decision = decision(for: run) {
            state.decided = GuardrailCopy.decided(decision)
        } else if let flag = flag(for: run) {
            state.question = GuardrailCopy.question(run, flag, now: now)
            state.acceptLabel = GuardrailCopy.accept(flag)
            state.keepLabel = GuardrailCopy.keep(flag)
        }
        return state
    }

    /// "Sun · 12 km (was 18)", today's next workout, "Nothing else today" or "Rest day".
    private func watchTodayLine() -> String {
        if let item = todayPlan.first(where: { completion(for: $0) == nil && $0.slot.end > now }) {
            if item.source == .swap, let title = swapTitles[item.id] { return title }
            return "\(Activity.title(item.slot.activityType)) · \(item.slot.minutes) min"
        }
        if let run = trainingRuns.first(where: { calendar.isDate($0.start, inSameDayAs: now) && !isPausedForReturn($0) }) {
            return run.title
        }
        // A day whose workouts are behind it (done or missed) isn't a rest day.
        return todayPlan.isEmpty ? "Rest day" : "Nothing else today"
    }

    /// Tomorrow's first workout for the complication after midnight.
    private func watchTomorrowLine() -> String {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return "Rest day" }
        if let item = plan.first(where: { calendar.isDate($0.slot.start, inSameDayAs: tomorrow) }) {
            if item.source == .swap, let title = swapTitles[item.id] { return title }
            return "\(Activity.title(item.slot.activityType)) · \(item.slot.minutes) min"
        }
        if let run = trainingRuns.first(where: { calendar.isDate($0.start, inSameDayAs: tomorrow) && !isPausedForReturn($0) }) {
            return run.title
        }
        return "Rest day"
    }

    /// Where an answer came from, for the Amplitude event only.
    enum AnswerSource { case watch, widget }

    /// A watch tap, recorded like a Lock Screen tap. A tap queued while the
    /// phone was away is dropped if its run has started or was already decided
    /// on the phone; the watch then shows what was decided (item 19). The phone
    /// widget's answers come through here too.
    @discardableResult
    func handleWatchAnswer(_ answer: WatchAnswer, from source: AnswerSource = .watch) -> Bool {
        func event(_ kind: String) -> AnalyticsEvent { source == .watch ? .watchAction(kind) : .widgetAction(kind) }
        guard let run = trainingRuns.first(where: { $0.key == answer.runKey }), run.start > Date() else {
            pushWatchState()
            return false
        }
        switch answer.kind {
        case .fresh, .tired, .sore:
            guard checkIn(for: run) == nil, let check = MorningCheck(rawValue: answer.kind.rawValue) else {
                pushWatchState()
                return false
            }
            answerMorningCheck(run, check)
            track(event("check_in"))
        case .accept, .keep:
            guard latestDecision(for: run) == nil, let flag = flag(for: run) else {
                pushWatchState()
                return false
            }
            if answer.kind == .accept { acceptSwap(run, flag: flag) } else { keepPlan(run, flag: flag) }
            track(event("swap"))
        }
        return true
    }

    /// The watch and the phone widget get the same state.
    func pushWatchState() {
        let state = watchState
        watchLink.send(state)
        pushWidgetState(state)
    }
}
