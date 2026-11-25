import Foundation

/// The push's first-miss comeback (range plan items 10–13), restored from
/// before commit 9179c3b: a missed workout gets one shorter comeback at 2×
/// points in the next free time within a day; a missed comeback isn't chased.
extension StandInAgent {
    /// At or under this many workouts a week, the push applies (item 10).
    static let pushPerWeek = 2.0

    func comebackActions(_ s: TickSnapshot, plan: [PlanItem], done: Set<String>, history: [Workout],
                         known: Set<String>, booked: inout [PlanItem], cal: Calendar) -> [AgentAction] {
        // A miss: the window ended (plus grace) after the plan was made, with no
        // workout. Swaps belong to the brake and routines to the plan; neither is chased.
        let missed = plan.filter {
            ($0.source == .plan || $0.source == .comeback)
                && !done.contains($0.id)
                && $0.slot.end.addingTimeInterval(Self.grace) <= s.now
                && $0.slot.end > s.planCreatedAt
        }
        var actions: [AgentAction] = []
        for item in missed {
            if item.source == .comeback {
                // No chasing: a missed comeback gets a quiet note, never a second comeback.
                let id = "note-missed-\(item.id)"
                if !known.contains(id) {
                    actions.append(AgentAction(
                        id: id, kind: .note, title: "Comeback skipped", planItemId: item.id, before: item.slot,
                        reason: "That's fine. Your next workout stays as planned.", createdAt: s.now
                    ))
                }
                continue
            }
            let id = "comeback-\(item.id)"
            guard !known.contains(id),
                  let slot = comebackSlot(for: item, history: history, booked: booked, busy: s.busy, now: s.now, cal: cal)
            else { continue }
            let points = item.points * 2
            booked.append(PlanItem(id: id, slot: slot, points: points, source: .comeback))
            actions.append(AgentAction(
                id: id, kind: .bookComeback, planItemId: id, before: item.slot, after: slot,
                reason: "Shorter sessions are easier to finish after a miss, and you usually work out around \(slot.start.clock).",
                points: points, createdAt: s.now
            ))
        }
        return actions
    }

    /// About 60% of the person's median workout (at least 10 minutes, rounded to
    /// 5), in their usual evening slot if it's still free today, otherwise the
    /// next free half hour before 9 PM, otherwise tomorrow at the usual time.
    func comebackSlot(for item: PlanItem, history: [Workout], booked: [PlanItem], busy: [Busy],
                      now: Date, cal: Calendar) -> Slot? {
        let lengths = history.map(\.minutes).sorted()
        let median = lengths.isEmpty ? 25 : lengths[lengths.count / 2]
        let minutes = max(10, Int((median * 0.6 / 5).rounded()) * 5)

        let eveningStarts = history
            .map { cal.component(.hour, from: $0.start) * 60 + cal.component(.minute, from: $0.start) }
            .filter { $0 >= 15 * 60 }
            .sorted()
        let usual = eveningStarts.isEmpty ? 18 * 60 + 30 : eveningStarts[eveningStarts.count / 2]
        let preferred = Int((Double(usual) / 30).rounded()) * 30

        let today = cal.startOfDay(for: now)
        let earliest = now.addingTimeInterval(30 * 60)
        func slot(on day: Date, at minuteOfDay: Int) -> Slot? {
            guard let start = cal.date(byAdding: .minute, value: minuteOfDay, to: day) else { return nil }
            return Slot(start: start, end: start.addingTimeInterval(Double(minutes) * 60), activityType: item.slot.activityType)
        }
        func free(_ candidate: Slot) -> Bool {
            candidate.start >= earliest
                && !booked.contains { $0.slot.start < candidate.end && $0.slot.end > candidate.start }
                && !busy.contains { $0.start < candidate.end && $0.end > candidate.start }
        }

        if let preferredToday = slot(on: today, at: preferred), free(preferredToday) { return preferredToday }
        for minuteOfDay in stride(from: 6 * 60, through: 21 * 60, by: 30) {
            if let candidate = slot(on: today, at: minuteOfDay), free(candidate) { return candidate }
        }
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return nil }
        return slot(on: tomorrow, at: preferred)
    }
}
