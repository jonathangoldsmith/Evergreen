import Foundation

/// Offline stand-in for the harness's `decide()`, so the miss loop runs on the
/// phone before the harness is deployed (P0a, eng review D14) and with no network
/// (one candidate answer to the open R2 question).
///
/// It implements the P0 rules from the plan: normal and goal with the
/// very-active cap, thin-history defaults (D8), duplicate merging (D9), misses,
/// comebacks at 2× points and points from completions, plus slot defense (P1
/// item 8, in StandInAgent+SlotDefense.swift). Routines and the load guardrail
/// stay with the harness. When the two disagree, the harness wins.
struct StandInAgent: Agent {
    var name: String { "Offline stand-in" }

    static let basePoints = 20
    /// A window counts as missed 30 minutes after it ends, and a workout up to 30
    /// minutes late still finishes it.
    static let grace: TimeInterval = 30 * 60

    func tick(_ s: TickSnapshot) async throws -> TickResponse {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: s.timeZone) ?? .current
        cal.firstWeekday = 2 // weeks start on Monday
        let day = cal.startOfDay(for: s.now)

        let counted = Self.mergeDuplicates(s.workouts)
            .filter { $0.minutes >= 10 && $0.start <= s.now }
            .sorted { $0.start < $1.start }
        let history = counted.filter { $0.start < day }

        // Normal and goal: 10% more than the last 4 weeks, rounded up (plan item 1).
        let historyDays = cal.dateComponents([.day], from: s.historyStart, to: day).day ?? 0
        let thin = historyDays < 14
        let windowStart = cal.date(byAdding: .day, value: -28, to: day)!
        let usual = thin ? 8 : history.filter { $0.start >= windowStart }.count
        let perWeek = Double(usual) / 4
        let goal = perWeek >= 6 ? usual : (usual * 11 + 9) / 10
        let normal = Normal(
            perWeek: perWeek,
            usual4Weeks: usual,
            goal4Weeks: goal,
            weeklyTarget: max(1, (goal + 3) / 4),
            gettingToKnowYou: thin
        )
        let weekStart = cal.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        let weekDone = counted.filter { $0.start >= weekStart }.count

        // Completions: each workout finishes the first open item that day whose
        // window hadn't already passed when the workout started.
        let plan = s.plan.sorted { $0.slot.start < $1.slot.start }
        var completions: [Completion] = []
        var done = Set<String>()
        for workout in counted {
            guard let item = plan.first(where: {
                !done.contains($0.id)
                    && cal.isDate($0.slot.start, inSameDayAs: workout.start)
                    && $0.slot.end.addingTimeInterval(Self.grace) >= workout.start
            }) else { continue }
            done.insert(item.id)
            completions.append(Completion(
                planItemId: item.id, workoutId: workout.id,
                points: item.points, comeback: item.source == .comeback
            ))
        }

        // Misses: the window ended (plus grace) after the plan was made, with no workout.
        let missed = plan.filter {
            !done.contains($0.id)
                && $0.slot.end.addingTimeInterval(Self.grace) <= s.now
                && $0.slot.end > s.planCreatedAt
        }

        var actions: [AgentAction] = []
        let known = Set(s.actions.map(\.id)).union(s.undoneActionIds)

        if thin, !known.contains("note-getting-to-know-you") {
            actions.append(AgentAction(
                id: "note-getting-to-know-you", kind: .note, title: "Getting to know you",
                reason: "You have less than two weeks of workouts, so I'm starting from 2 a week.",
                createdAt: s.now
            ))
        }

        var booked = plan
        for item in missed {
            if item.source == .comeback {
                // State table: an also-missed comeback gets no new card, only a feed note.
                let id = "note-missed-\(item.id)"
                if !known.contains(id) {
                    actions.append(AgentAction(
                        id: id, kind: .note, title: "Comeback skipped", planItemId: item.id,
                        before: item.slot,
                        reason: "That's fine. Your next workout stays as planned.",
                        createdAt: s.now
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
                id: id, kind: .bookComeback, planItemId: id,
                before: item.slot, after: slot,
                reason: "Shorter sessions are easier to finish after a miss, and you usually work out around \(slot.start.formatted(date: .omitted, time: .shortened)).",
                points: points, createdAt: s.now
            ))
        }

        // Slot defense: an upcoming workout a busy time landed on moves before
        // it can be missed. One action per workout and conflict, so an undone
        // move isn't made again.
        for item in booked.sorted(by: { $0.slot.start < $1.slot.start })
        where !done.contains(item.id) && item.slot.start > s.now {
            guard let conflict = s.busy.first(where: { $0.start < item.slot.end && $0.end > item.slot.start }) else {
                continue
            }
            let id = "defend-\(item.id)-\(Int(conflict.start.timeIntervalSince1970))"
            guard !known.contains(id),
                  let slot = Self.defendedSlot(
                      for: item, conflict: conflict, busy: s.busy,
                      others: booked.filter { $0.id != item.id }, now: s.now, cal: cal
                  ),
                  let index = booked.firstIndex(where: { $0.id == item.id })
            else { continue }
            booked[index].slot = slot
            let shrunk = slot.minutes < item.slot.minutes
            let at = conflict.start.formatted(date: .omitted, time: .shortened)
            actions.append(AgentAction(
                id: id, kind: shrunk ? .shrink : .move, planItemId: item.id,
                before: item.slot, after: slot,
                reason: shrunk
                    ? "Your calendar is busy around \(at), so I made it \(slot.minutes) minutes to fit."
                    : "That's the nearest free time, so it stays close to when you planned it.",
                createdAt: s.now
            ))
        }

        return TickResponse(
            actions: actions,
            completions: completions,
            pointsTotal: completions.reduce(0) { $0 + $1.points },
            weekDone: weekDone,
            normal: normal
        )
    }

    /// About 60% of the person's median workout, rounded to 5 minutes, in their
    /// usual evening slot if it's still free today, otherwise the next free half
    /// hour before 9 PM, otherwise tomorrow at the usual time.
    private func comebackSlot(
        for item: PlanItem, history: [Workout], booked: [PlanItem], busy: [Busy], now: Date, cal: Calendar
    ) -> Slot? {
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
        func slot(on day: Date, at minuteOfDay: Int) -> Slot {
            let start = cal.date(byAdding: .minute, value: minuteOfDay, to: day)!
            return Slot(start: start, end: start.addingTimeInterval(Double(minutes) * 60),
                        activityType: item.slot.activityType)
        }
        func free(_ candidate: Slot) -> Bool {
            candidate.start >= earliest
                && !booked.contains { $0.slot.start < candidate.end && $0.slot.end > candidate.start }
                && !busy.contains { $0.start < candidate.end && $0.end > candidate.start }
        }

        let preferredToday = slot(on: today, at: preferred)
        if free(preferredToday) { return preferredToday }
        for minuteOfDay in stride(from: 6 * 60, through: 21 * 60, by: 30) {
            let candidate = slot(on: today, at: minuteOfDay)
            if free(candidate) { return candidate }
        }
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        return slot(on: tomorrow, at: preferred)
    }

    /// Same-type workouts overlapping by more than half of the shorter one count
    /// once, keeping the longer (eng review D9).
    static func mergeDuplicates(_ workouts: [Workout]) -> [Workout] {
        var kept: [Workout] = []
        for workout in workouts.sorted(by: { $0.minutes > $1.minutes }) {
            let duplicate = kept.contains { other in
                guard other.activityType == workout.activityType else { return false }
                let overlap = min(other.end, workout.end).timeIntervalSince(max(other.start, workout.start))
                return overlap > min(other.minutes, workout.minutes) * 60 / 2
            }
            if !duplicate { kept.append(workout) }
        }
        return kept
    }
}
