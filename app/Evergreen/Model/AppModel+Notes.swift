import Foundation

/// Guardrail notifications (plan items 7 and 17): what to schedule, and what
/// each Lock Screen button does.
extension AppModel {
    /// The notes for the training runs ahead and this Sunday's pain question,
    /// within the 2-a-day budget (design decision 10, R9).
    var guardrailNotes: [GuardrailNote] {
        let states = trainingRuns.filter { !isPausedForReturn($0) }.map { run in
            GuardrailSchedule.RunState(
                run: run,
                // From history alone: the morning answer comes later.
                flag: GuardrailRule.flag(for: run, .init(history: workouts, injuryMonth: profile.injuryMonth, check: nil,
                                                         upcoming: trainingRuns, calendar: calendar)),
                decided: latestDecision(for: run) != nil,
                checkedIn: checkIn(for: run) != nil
            )
        }
        let thisWeek = PainWeek.monday(of: Date(), calendar: calendar)
        let painWeeks = onboarded && painRecord(for: thisWeek) == nil ? [thisWeek] : []
        return GuardrailSchedule.notes(runs: states, painWeeks: painWeeks, bedtimes: bedtimes(before: Date()), now: Date(),
                                      calendar: calendar)
    }

    /// A Lock Screen button. The first answer wins: a swap already decided in
    /// the app (or on the watch) isn't decided again.
    func handleNotificationAction(_ action: NotificationAction, _ payload: NotePayload?) async {
        switch action {
        case .swapAccept, .swapKeep:
            guard let run = payload?.run, let flag = payload?.flag, latestDecision(for: run) == nil else { return }
            if action == .swapAccept {
                acceptSwap(run, flag: flag)
                let copy = (title: flag.keepEasy ? "Running it easy" : "Changed to \(flag.suggested.label)",
                            body: GuardrailCopy.sourceNote(run, flag.planned))
                let undo = NotificationAction.fixedCategories.first { $0.identifier == NotificationAction.swapDoneCategory }
                await notifier.sendNow(copy, id: "swap-done-\(run.swapItemId)", category: undo,
                                       payload: NotePayload(run: run, flag: flag))
            } else {
                keepPlan(run, flag: flag)
            }
        case .swapUndo:
            guard let run = payload?.run, let decision = decision(for: run) else { return }
            undoDecision(decision)
        case .checkFresh, .checkTired, .checkSore:
            guard let run = payload?.run, let answer = action.morningCheck else { return }
            if checkIn(for: run) == nil { answerMorningCheck(run, answer) }
            // "Sore" on a long run: ask about the swap right there.
            if latestDecision(for: run) == nil, let flag = flag(for: run) {
                let copy = (title: GuardrailCopy.question(run, flag, now: now), body: GuardrailCopy.reason(flag))
                let id = "swap-\(StableHash.hex(run.key, length: 12))"
                await notifier.sendNow(copy, id: id, category: NotificationAction.swapCategory(id: id, flag: flag),
                                       payload: NotePayload(run: run, flag: flag))
            }
        case .painNo, .painALittle, .painYes:
            guard let answer = action.painAnswer,
                  let week = payload?.weekStart ?? PainWeek.openWeek(at: now, calendar: calendar) else { return }
            answerPain(answer, week: week)
        }
    }
}
