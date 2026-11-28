import Foundation
import SwiftData

/// The brake on Today (plan items 5–8): flags on training-calendar runs, the
/// swap or keep the person chose, and the morning check.
extension AppModel {
    /// How far ahead training calendars are read: today plus a week.
    static let trainingWindowDays = 8

    // MARK: Flags

    /// This run's flag, from the person's runs, injury month, morning answer
    /// and, for a run today, this morning's readings.
    func flag(for run: PlannedRun) -> GuardrailFlag? {
        let range = calendar.isDate(run.start, inSameDayAs: now) ? todayRange : nil
        return GuardrailRule.flag(for: run, GuardrailRule.Context(
            history: workouts, injuryMonth: profile.injuryMonth, check: checkIn(for: run),
            upcoming: trainingRuns, calendar: .current, body: bodySignal(for: run),
            loadCeiling: range.map { Double($0.ceiling) - minutesDone(on: now) }
        ))
    }

    // MARK: Today's range

    /// Today's range (TODOS item 3), or nil with under two weeks of history.
    var todayRange: TodayRange? { range(on: now) }

    /// The range a day had, from the workouts before it and that morning's readings.
    func range(on day: Date) -> TodayRange? {
        let planned = todayPlanned(on: day)
        let bodyOff = BodySignal.read(healthDays, on: day, calendar: calendar).isOff
        return TodayRange.make(workouts: workouts, on: day, planned: planned, bodyOff: bodyOff, calendar: calendar)
    }

    /// Training minutes logged on that day.
    func minutesDone(on day: Date) -> Double {
        workouts.filter { calendar.isDate($0.start, inSameDayAs: day) }.reduce(0) { $0 + $1.minutes }
    }

    private func todayPlanned(on day: Date) -> Bool {
        plan.contains { calendar.isDate($0.slot.start, inSameDayAs: day) }
            || trainingRuns.contains { calendar.isDate($0.start, inSameDayAs: day) && !isPausedForReturn($0) }
    }

    /// Readiness: this morning's readings against the person's usual, for a
    /// run today only (last night's sleep says nothing about Sunday).
    func bodySignal(for run: PlannedRun) -> BodySignal? {
        guard calendar.isDate(run.start, inSameDayAs: now) else { return nil }
        let signal = BodySignal.read(healthDays, on: now, calendar: calendar)
        return signal.off.isEmpty ? nil : signal
    }

    /// Sleep, resting heart rate and HRV by day: from Apple Health for the
    /// person's own week, or what a demo beat set.
    var healthDays: [HealthHistory.Day] {
        persona.key.isReal ? health.days : demoHealthDays
    }

    func checkIn(for run: PlannedRun) -> MorningCheck? {
        checkIns.last { $0.runKey == run.key }?.answer
    }

    /// The newest decision for this run that Evergreen hasn't withdrawn,
    /// undone ones included, so the card can tell "never asked" from "undone".
    func latestDecision(for run: PlannedRun) -> GuardrailDecision? {
        decisions.last { $0.runKey == run.key && !$0.cancelled }
    }

    /// The decision in effect for this run, if any.
    func decision(for run: PlannedRun) -> GuardrailDecision? {
        latestDecision(for: run).flatMap { $0.undone ? nil : $0 }
    }

    /// Runs that need something on Today, soonest first: a flag to decide or
    /// a decision still undoable, today's morning check, or its answer (design
    /// decision 7). Only runs that haven't started (eng re-run: Undo stays
    /// live until the run starts).
    var guardrailRuns: [PlannedRun] {
        let horizon = Date(timeInterval: 36 * 3600, since: now)
        return trainingRuns.filter { run in
            guard run.start > now, run.start < horizon, !isPausedForReturn(run) else { return false }
            return decision(for: run) != nil || flag(for: run) != nil || needsMorningCheck(run) || checkIn(for: run) != nil
        }
    }

    /// Run days get "How do your legs feel?" until the run starts (plan item 7):
    /// from 5 AM, or from 8 PM the evening before for a run before 6 AM. Two
    /// runs in one day are asked about once, for the first (design decision 7).
    func needsMorningCheck(_ run: PlannedRun) -> Bool {
        guard run.size != nil, checkIn(for: run) == nil, decision(for: run) == nil, run.start > now,
              firstSizedRun(onDayOf: run)?.key == run.key
        else { return false }
        return now >= MorningCheckTiming.opens(for: run, calendar: .current)
    }

    /// The day's first run with a size, so a day is asked about once.
    func firstSizedRun(onDayOf run: PlannedRun) -> PlannedRun? {
        trainingRuns
            .filter { $0.size != nil && !isPausedForReturn($0) && calendar.isDate($0.start, inSameDayAs: run.start) }
            .min { $0.start < $1.start }
    }

    // MARK: Choices

    /// "Make it 12 km": adds the swap to Evergreen's calendar; the training
    /// calendar's own event is never touched (item 8).
    func acceptSwap(_ run: PlannedRun, flag: GuardrailFlag) {
        context.insert(GuardrailDecision(run: run, flag: flag, choice: .accept, at: Date()))
        save()
        recordChoice("accept", run: run, flag: flag)
    }

    /// "Keep 18 km".
    func keepPlan(_ run: PlannedRun, flag: GuardrailFlag) {
        context.insert(GuardrailDecision(run: run, flag: flag, choice: .keep, at: Date()))
        save()
        recordChoice("keep", run: run, flag: flag)
    }

    /// The flag and the choice go to the harness (item 9) and, as words only, to Amplitude.
    private func recordChoice(_ choice: String, run: PlannedRun, flag: GuardrailFlag) {
        upload(.flag(flag, run: run, at: Date(), calendar: calendar))
        upload(.choice(choice, kind: flag.kind, run: run, at: Date(), calendar: calendar))
        track(.choice(choice))
    }

    /// Counts a flag as shown once per run per launch.
    func noteFlagShown(_ run: PlannedRun, _ flag: GuardrailFlag) {
        guard flagsShown.insert(run.key + flag.kind.rawValue).inserted else { return }
        track(.flagShown(flag.kind))
    }

    /// Queues an event for the harness once uploads are allowed (BN2). Runs
    /// and choices go up only for the person's own week, not a demo person's;
    /// the owner's own answers (consent, injury, pain) always count.
    func upload(_ event: UploadEvent, ownAnswer: Bool = false) {
        guard profile.uploadsAllowed == true, ownAnswer || persona.key.isReal else { return }
        outbox.enqueue(event)
        Task { await outbox.flush() }
    }

    /// Undo on a decided run. Undoing a swap keeps the plan, so a flag fires
    /// once per run and the choice sticks (item 5); undoing a keep asks again.
    func undoDecision(_ decision: GuardrailDecision) {
        guard !decision.undone else { return }
        decision.undone = true
        upload(.choice("undo", kind: decision.flagKind, run: decision.plannedRun, at: Date(), calendar: calendar))
        track(.choice("undo"))
        if decision.choice == .accept {
            let run = trainingRuns.first { $0.key == decision.runKey } ?? decision.plannedRun
            context.insert(GuardrailDecision(run: run, flag: decision.flag, choice: .keep, at: Date()))
        }
        save()
    }

    func answerMorningCheck(_ run: PlannedRun, _ answer: MorningCheck) {
        context.insert(CheckInRecord(runKey: run.key, answer: answer, at: Date()))
        save()
        upload(.checkIn(answer, run: run, at: Date(), calendar: calendar))
    }

    // MARK: Swaps on the plan

    /// One plan item per swap in effect, at the run's start time, sized to the
    /// suggestion (item 8). It replaces nothing on the training calendar.
    var swapItems: [PlanItem] {
        let accepted = Dictionary(decisions.filter { $0.inEffect }.map { ($0.runKey, $0) }, uniquingKeysWith: { $1 })
        return accepted.values.filter { $0.choice == .accept }.map { decision in
            let ratio = decision.plannedValue > 0 ? decision.suggestedValue / decision.plannedValue : 1
            let minutes = decision.unit == .minutes
                ? decision.suggestedValue
                : decision.runEnd.timeIntervalSince(decision.runStart) / 60 * ratio
            let start = decision.runStart
            return PlanItem(
                id: "swap-\(StableHash.hex(decision.runKey, length: 12))",
                slot: Slot(start: start, end: start.addingTimeInterval(max(minutes, 10) * 60), activityType: "Running"),
                points: StandInAgent.basePoints, source: .swap
            )
        }
    }

    /// Calendar titles for swaps: "Easy run 12 km (was 18 km)".
    var swapTitles: [String: String] {
        var titles: [String: String] = [:]
        for decision in decisions where decision.inEffect && decision.choice == .accept {
            let id = "swap-\(StableHash.hex(decision.runKey, length: 12))"
            titles[id] = decision.keepEasy
                ? "Easy run \(decision.planned.label)"
                : "Easy run \(decision.suggested.label) (was \(decision.planned.label))"
        }
        return titles
    }

    /// Withdraws swaps whose run is no longer on the training calendar (moved,
    /// renamed or deleted), as Evergreen's own cancel, not the person's Undo,
    /// so the replacement run can be flagged again (item 8). Only runs inside
    /// the window just read, so a run outside it is never withdrawn by mistake.
    func withdrawOrphanedSwaps(window: Range<Date>) {
        let keys = Set(trainingRuns.map(\.key))
        var changed = false
        for decision in decisions where decision.inEffect && window.contains(decision.runStart)
            && decision.runStart > now && !keys.contains(decision.runKey) {
            decision.cancelled = true
            changed = true
        }
        if changed { try? context.save() }
    }
}

// MARK: The week's count (eng re-run task E19)

extension AppModel {
    /// Training-calendar runs in the plan's week that aren't shown as a swap.
    var weekTrainingRuns: [PlannedRun] {
        let swapped = Set(swapItems.map(\.id))
        let end = calendar.date(byAdding: .day, value: 7, to: storyDay) ?? storyDay
        return trainingRuns.filter {
            $0.start >= storyDay && $0.start < end && !swapped.contains($0.swapItemId) && !isPausedForReturn($0)
        }
    }

    /// Every workout this week, counted once: Evergreen's plan (swaps included)
    /// and the training calendar's runs, so a kept run counts like a swapped one.
    var weekTotal: Int { plan.count + weekTrainingRuns.count }

    var weekDone: Int {
        plan.filter { completion(for: $0) != nil }.count + weekTrainingRuns.filter(isDone).count
    }

    /// A training run is done when Apple Health has a run that day.
    func isDone(_ run: PlannedRun) -> Bool {
        workouts.contains { $0.activityType == "Running" && calendar.isDate($0.start, inSameDayAs: run.start) }
    }
}
