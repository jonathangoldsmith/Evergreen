import Foundation

/// The push (range plan items 10–16): logging the miss and comeback, and the
/// demo beats that show it with Sam.
extension AppModel {
    /// A comeback the agent booked: the miss and the offer go to the harness
    /// (item 16), and Amplitude counts it with no durations.
    func notePush(_ action: AgentAction) {
        guard action.kind == .bookComeback, let after = action.after else { return }
        if let before = action.before, let missed = action.planItemId.map({ String($0.dropFirst("comeback-".count)) }) {
            upload(.miss(PlanItem(id: missed, slot: before, points: 0, source: .plan), at: Date(), calendar: calendar))
        }
        upload(.comeback("offered", item: after, points: action.points, comebackId: action.id, at: Date(), calendar: calendar))
        track(.comebackBooked)
    }

    func noteComebackDone(_ completion: Completion) {
        if let item = plan.first(where: { $0.id == completion.planItemId }) {
            upload(.comeback("completed", item: item.slot, points: completion.points, comebackId: item.id,
                             at: Date(), calendar: calendar))
        }
        track(.comebackDone)
    }

    // MARK: Demo beats

    /// Sam at 1:30 PM: the noon walk was missed, so the agent books a shorter
    /// comeback tonight for double points.
    func showComebackDemo() {
        calendarSync.removeAllEvents(around: storyDay)
        switchPerson(to: .sam, clock: 13 * 60 + 30)
    }

    /// Sam finishes the comeback: a walk is logged at its time, and the Done
    /// sheet shows the 2× points.
    func finishComebackDemo() {
        guard let comeback = plan.first(where: { $0.source == .comeback && completion(for: $0) == nil }) else { return }
        logWorkout(Workout(id: "demo-\(UUID().uuidString)", activityType: comeback.slot.activityType,
                           start: comeback.slot.start, end: comeback.slot.end, effort: nil, avgHeartRate: nil,
                           source: .demo))
        setClock(to: comeback.slot.end.addingTimeInterval(5 * 60))
    }

    /// Demo control: a workout as if Apple Health had it.
    func logWorkout(_ workout: Workout) {
        let record = LoggedWorkout(workout)
        context.insert(record)
        runWorkoutsAppend(record)
        save()
        Task { await tick() }
    }

    /// Demo control: "now" moves within the story day.
    func setClock(to date: Date) {
        setClockMinutes(Int(date.timeIntervalSince(storyDay) / 60))
        save()
        Task { await tick() }
    }
}
