import Foundation

extension AppModel {
    // MARK: The card stack (G2, E17)

    /// Today's cards in urgency order: run decisions, the pain check-in, the
    /// return plan, then the agent's latest action while its Undo is live.
    var todayCards: [TodayCard] {
        var ranked: [TodayCard.Ranked] = guardrailRuns.map { run in
            TodayCard.Ranked(card: .run(run), urgency: runUrgency(run), at: run.start)
        }
        if let week = painCardWeek {
            let answered = painRecord(for: week) != nil
            ranked.append(.init(card: .pain(week), urgency: answered ? .note : .pain, at: week))
        }
        if showsReturnCard {
            ranked.append(.init(card: .returnPlan, urgency: .returnPlan, at: returnPlan?.start ?? now))
        }
        if let action = latestAction, let urgency = actionUrgency(action) {
            ranked.append(.init(card: .action(action), urgency: urgency, at: now))
        }
        return TodayCard.ordered(ranked)
    }

    /// The most urgent run on Today, for the watch.
    var mostUrgentRun: PlannedRun? {
        todayCards.lazy.compactMap { card -> PlannedRun? in
            if case .run(let run) = card { return run }
            return nil
        }.first
    }

    func runUrgency(_ run: PlannedRun) -> TodayUrgency {
        if decision(for: run) != nil { return .undoable }
        if flag(for: run) != nil { return .swap }
        if needsMorningCheck(run) { return .morningCheck }
        return .note
    }

    /// An agent action is a card while its Undo is live: until the workout it
    /// set up starts or is done (eng re-run Section 1 #2). Then it's a plan row
    /// with its badge. Purchases keep their own card, and notes stay as notes.
    func actionUrgency(_ action: AgentAction) -> TodayUrgency? {
        if let purchaseId = action.purchaseId {
            return purchaseState(purchaseId)?.status == .awaitingApproval ? .ask : .undoable
        }
        if action.kind == .note { return .note }
        guard let id = action.planItemId, let item = plan.first(where: { $0.id == id }),
              completion(for: item) == nil, item.slot.start > now
        else { return nil }
        return .undoable
    }

    /// The return-plan card: the offer, the plan in progress or paused, and a
    /// day of "Back to your plan." or the ended card's Undo (item 21).
    var showsReturnCard: Bool {
        if offersReturnPlan { return true }
        guard let plan = returnPlan else { return false }
        switch plan.status {
        case .active, .paused: return true
        case .ended, .finished: return (plan.endedAt ?? .distantPast) > Date().addingTimeInterval(-86_400)
        }
    }

    /// The pain card: the open week's question, or its "Thanks" for the rest
    /// of the day it was answered (design decision 7).
    var painCardWeek: Date? {
        if let week = pendingPainWeek { return week }
        guard ostrcWeek == nil, let week = PainWeek.openWeek(at: now, calendar: calendar),
              let record = painRecord(for: week), record.answer != .noAnswer,
              calendar.isDate(record.createdAt, inSameDayAs: Date())
        else { return nil }
        return week
    }

    // MARK: Badges

    /// The move or shrink still in effect that last changed this workout, for
    /// the "Moved" badge on its row.
    func movedAction(for item: PlanItem) -> AgentAction? {
        appliedActions.last {
            $0.planItemId == item.id && ($0.kind == .move || $0.kind == .shrink) && !isUndone($0)
        }
    }

    /// How many workouts are on the plan: "three".
    var planCountWord: String { Self.word(plan.count) }

    /// "three" for 3; numerals past ten.
    static func word(_ number: Int) -> String {
        guard (0...10).contains(number) else { return "\(number)" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        return formatter.string(from: number as NSNumber) ?? "\(number)"
    }
}

// MARK: Demo beats for the card stack (G4)

extension AppModel {
    /// Run morning: an easy 40-minute run at 6 PM on a Runna-style calendar,
    /// and the clock at 8 AM, so Today asks "How do your legs feel?".
    func showMorningCheckDemo() {
        resetDemo()
        let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: storyDay) ?? storyDay
        setClockMinutes(8 * 60)
        let id = calendarSync.addDemoTrainingWeek([("Easy 40 min", evening, 40)])
        if let id { setTrainingCalendars(profile.trainingCalendarIds.union([id])) } else { save() }
    }

    /// This week's Sunday at 6:30 PM: the pain question is open, and
    /// tomorrow's 2½-hour long run is a big jump, so two cards stack.
    func showSundayDemo() {
        resetDemo()
        let week = PainWeek.monday(of: storyDay, calendar: calendar)
        let sunday = PainWeek.asksAt(week, calendar: calendar).addingTimeInterval(30 * 60)
        setClockMinutes(Int(sunday.timeIntervalSince(storyDay) / 60))
        let monday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: sunday)) ?? sunday
        let longRun = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: monday) ?? monday
        let id = calendarSync.addDemoTrainingWeek([("Long run 2h 30", longRun, 150)])
        if let id { setTrainingCalendars(profile.trainingCalendarIds.union([id])) } else { save() }
    }
}
