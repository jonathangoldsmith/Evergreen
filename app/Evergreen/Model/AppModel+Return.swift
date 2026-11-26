import Foundation
import SwiftData

/// The return-to-running plan on Today (range plan item 21, design decision
/// 19): offered after a recent injury, started only on a yes, its sessions on
/// Evergreen's calendar, external runs paused while it runs, and paused by a
/// "Yes" pain answer. No Amplitude event: starting one would reveal an injury.
extension AppModel {
    /// An injury this recent brings the offer (item 21).
    static let returnOfferMonths = 3
    static let offerDismissedKey = "return_offer_dismissed_for"

    /// The newest plan, whatever its state.
    var returnPlan: ReturnPlanState? { returnPlans.last }

    /// The offer card: an injury in the last 3 months, no plan since it, and not dismissed for that injury.
    var offersReturnPlan: Bool {
        guard let injury = profile.injuryMonth,
              let since = calendar.date(byAdding: .month, value: -Self.returnOfferMonths, to: calendar.startOfDay(for: now)),
              injury >= (calendar.dateInterval(of: .month, for: since)?.start ?? since)
        else { return false }
        if let plan = returnPlan, plan.status == .active || plan.status == .paused || plan.createdAt >= injury {
            return false
        }
        return UserDefaults.standard.double(forKey: Self.offerDismissedKey) != injury.timeIntervalSince1970
    }

    func dismissReturnOffer() {
        guard let injury = profile.injuryMonth else { return }
        UserDefaults.standard.set(injury.timeIntervalSince1970, forKey: Self.offerDismissedKey)
        save()
    }

    /// Sessions still ahead in an active plan.
    var returnSessions: [ReturnPlan.Session] {
        guard let plan = returnPlan, plan.status == .active else { return [] }
        return ReturnPlan.sessions(from: plan.start, weekdays: plan.weekdays, startMinute: plan.startMinute,
                                   fromWeek: plan.fromWeek, calendar: calendar)
    }

    /// "Week 2 of 4": the week of the next session, or the last one.
    var returnWeek: Int? {
        let sessions = returnSessions
        guard !sessions.isEmpty else { return returnPlan?.pausedWeek }
        return (sessions.first { $0.end > now } ?? sessions.last)?.week
    }

    /// The plan's sessions in the week shown, as Evergreen plan items.
    var returnItems: [PlanItem] {
        let end = calendar.date(byAdding: .day, value: Self.trainingWindowDays, to: storyDay) ?? storyDay
        return returnSessions.filter { $0.start >= storyDay && $0.start < end }.map { session in
            PlanItem(id: returnItemId(session), slot: Slot(start: session.start, end: session.end, activityType: "Running"),
                     points: StandInAgent.basePoints, source: .returnSession)
        }
    }

    var returnTitles: [String: String] {
        Dictionary(returnSessions.map { (returnItemId($0), $0.title) }, uniquingKeysWith: { $1 })
    }

    private func returnItemId(_ session: ReturnPlan.Session) -> String {
        "return-\(Int(session.start.timeIntervalSince1970))"
    }

    /// External runs stay paused while a plan is active or paused (item 21):
    /// pain is exactly when the brake matters most.
    func isPausedForReturn(_ run: PlannedRun) -> Bool {
        guard let plan = returnPlan, plan.status == .active || plan.status == .paused else { return false }
        return run.start >= plan.start
    }

    // MARK: Choices

    /// "Start 4 weeks, 3 days a week": nothing starts without this yes.
    func startReturnPlan(weekdays: Set<Int>, startMinute: Int) {
        context.insert(ReturnPlanState(start: Date(), weekdays: weekdays, startMinute: startMinute, at: Date()))
        save()
    }

    /// "End return plan", with Undo: external runs come back, and the first is
    /// checked by the spike rule as usual.
    func endReturnPlan() {
        guard let plan = returnPlan, plan.status == .active || plan.status == .paused else { return }
        plan.status = .ended
        plan.endedAt = Date()
        save()
    }

    func undoEndReturnPlan() {
        guard let plan = returnPlan, plan.status == .ended else { return }
        plan.status = plan.pausedWeek == nil ? .active : .paused
        plan.endedAt = nil
        save()
    }

    /// A "Yes" pain answer during the plan pauses it (item 21).
    func pauseReturnPlan() {
        guard let plan = returnPlan, plan.status == .active else { return }
        plan.pausedWeek = returnWeek ?? plan.fromWeek
        plan.status = .paused
        save()
    }

    /// Resuming picks up at the week it paused and asks first, like starting.
    func resumeReturnPlan() {
        guard let plan = returnPlan, plan.status == .paused else { return }
        plan.start = Date()
        plan.fromWeek = plan.pausedWeek ?? plan.fromWeek
        plan.pausedWeek = nil
        plan.status = .active
        save()
    }

    /// A plan whose last session has passed hands back to the normal plan.
    func finishReturnPlanIfDone() {
        guard let plan = returnPlan, plan.status == .active else { return }
        let all = ReturnPlan.sessions(from: plan.start, weekdays: plan.weekdays, startMinute: plan.startMinute,
                                      fromWeek: plan.fromWeek, calendar: calendar)
        guard let last = all.last, last.end.addingTimeInterval(StandInAgent.grace) < now else { return }
        plan.status = .finished
        plan.endedAt = Date()
        try? context.save()
    }

    // MARK: Demo

    /// Demo control: an injury last month, so Today offers the return plan.
    func showReturnDemo() {
        resetDemo()
        returnPlans.forEach(context.delete)
        UserDefaults.standard.removeObject(forKey: Self.offerDismissedKey)
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        profile.injuryMonth = calendar.dateInterval(of: .month, for: lastMonth)?.start
        profile.injuryAnswered = true
        save()
    }
}
