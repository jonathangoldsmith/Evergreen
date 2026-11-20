import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class AppModel {
    private let context: ModelContext
    /// The saved run (see Storage.swift). SwiftData models are observable, so
    /// views that read through this class update when the run changes.
    private let run: Run
    private(set) var persona: Persona
    /// The last good answer, decoded once from `run.lastResponse`.
    private(set) var response: TickResponse?
    private(set) var offline = false
    private(set) var agentName = ""
    /// Set when a workout finishes a plan item; drives the Done sheet.
    var celebration: Completion?

    private let calendar = Calendar.current
    /// Counts ticks so only the newest one's answer is applied. Ticks overlap
    /// (a clock change right after a logged workout), and a slow harness reply
    /// to an older snapshot must not replace a newer one.
    @ObservationIgnored private var latestTick = 0

    init(context: ModelContext) {
        self.context = context
        let today = Calendar.current.startOfDay(for: Date())
        let saved = (try? context.fetch(FetchDescriptor<Run>()))?.first
        let run = saved ?? Run(persona: .sam, storyDay: today)
        if saved == nil { context.insert(run) }
        self.run = run
        persona = Persona.load(run.personaKey, storyDay: today)
        response = nil
        if run.storyDay != today {
            // A new day is a new story day: keep the person and onboarding, drop the run.
            clearRun(storyDay: today)
        } else {
            response = run.lastResponse.flatMap { try? JSONDecoder.contract.decode(TickResponse.self, from: $0) }
        }
        save()
    }

    // MARK: Derived

    var onboarded: Bool { run.onboarded }

    /// The demo's person. Picking a different one starts a fresh run for them.
    var personKey: PersonaKey {
        get { persona.key }
        set {
            guard newValue != persona.key else { return }
            switchPerson(to: newValue)
        }
    }
    var clockMinutes: Int? { run.clockMinutes }
    var storyDay: Date { run.storyDay }

    var now: Date {
        guard let minutes = run.clockMinutes else { return Date() }
        return calendar.date(byAdding: .minute, value: minutes, to: storyDay) ?? Date()
    }

    var normal: Normal? { response?.normal }

    var basePlan: [PlanItem] { PinnedPlan.items(for: persona.key, storyDay: storyDay) }

    /// The pinned plan with every applied, not-undone action on top. Undoing an
    /// action just drops it from this replay.
    var plan: [PlanItem] {
        var items = basePlan
        for action in appliedActions where !isUndone(action) {
            guard let id = action.planItemId, let after = action.after else { continue }
            switch action.kind {
            case .bookComeback, .addRoutine:
                items.append(PlanItem(
                    id: id, slot: after, points: action.points ?? StandInAgent.basePoints,
                    source: action.kind == .bookComeback ? .comeback : .routine
                ))
            case .move, .shrink:
                if let index = items.firstIndex(where: { $0.id == id }) { items[index].slot = after }
            case .note:
                break
            }
        }
        return items.sorted { $0.slot.start < $1.slot.start }
    }

    var todayPlan: [PlanItem] { plan.filter { calendar.isDate($0.slot.start, inSameDayAs: storyDay) } }

    var workouts: [Workout] {
        persona.workouts + run.workouts.map(\.workout).sorted { $0.start < $1.start }
    }

    /// Every applied action, oldest first, undone ones included.
    private var records: [ActionRecord] { run.actions.sorted { $0.sequence < $1.sequence } }
    private var appliedActions: [AgentAction] { records.map(\.action) }
    private var undoneIds: Set<String> { Set(run.actions.filter(\.undone).map(\.actionId)) }

    /// Newest first.
    var feed: [AgentAction] { appliedActions.reversed() }

    /// The one card on Today: the latest action that's still in effect.
    var latestAction: AgentAction? { feed.first { !isUndone($0) } }

    func isUndone(_ action: AgentAction) -> Bool { undoneIds.contains(action.id) }

    func completion(for item: PlanItem) -> Completion? {
        response?.completions.first { $0.planItemId == item.id }
    }

    func isMissed(_ item: PlanItem) -> Bool {
        completion(for: item) == nil && item.slot.end.addingTimeInterval(StandInAgent.grace) <= now
    }

    /// The action that created a plan item, if any (for the comeback badge).
    func creatingAction(for item: PlanItem) -> AgentAction? {
        appliedActions.first { $0.planItemId == item.id && $0.kind == .bookComeback }
    }

    // MARK: Agent

    /// Ticks now, then every minute while the app is on screen, so a window that
    /// passes with the app open still gets its comeback.
    func keepTicking() async {
        while !Task.isCancelled {
            await tick()
            try? await Task.sleep(for: .seconds(60))
        }
    }

    func tick() async {
        latestTick += 1
        let thisTick = latestTick
        let agent = AgentChoice.current()
        agentName = agent.name
        let snapshot = TickSnapshot(
            now: now,
            timeZone: calendar.timeZone.identifier,
            persona: persona.key.rawValue,
            historyStart: persona.historyStart,
            planCreatedAt: PinnedPlan.createdAt(storyDay: storyDay),
            plan: plan,
            workouts: workouts,
            actions: appliedActions.filter { !isUndone($0) },
            undoneActionIds: records.filter(\.undone).map(\.actionId)
        )
        do {
            let response = try await agent.tick(snapshot)
            guard thisTick == latestTick else { return }
            offline = false
            apply(response)
        } catch {
            guard thisTick == latestTick else { return }
            // Keep the last good screen up with a quiet label (design D5).
            offline = true
        }
    }

    private func apply(_ response: TickResponse) {
        let known = Set(run.actions.map(\.actionId))
        for action in response.actions where !known.contains(action.id) {
            record(action)
        }
        self.response = response
        run.lastResponse = try? JSONEncoder.contract.encode(response)
        if let fresh = response.completions.first(where: { !run.seenCompletions.contains($0.planItemId) }) {
            run.seenCompletions += response.completions.map(\.planItemId)
            celebration = fresh
        }
        save()
    }

    // MARK: Person's choices

    func undo(_ action: AgentAction) {
        guard let record = run.actions.first(where: { $0.actionId == action.id }), !record.undone else { return }
        record.undone = true
        save()
        Task { await tick() }
    }

    /// "Pick another time": logged as the person's own move so it shows in the feed.
    func move(_ item: PlanItem, to start: Date) {
        let after = Slot(start: start, end: start.addingTimeInterval(item.slot.end.timeIntervalSince(item.slot.start)),
                         activityType: item.slot.activityType)
        record(AgentAction(
            id: "user-move-\(UUID().uuidString)", kind: .move, planItemId: item.id,
            before: item.slot, after: after, reason: "You picked this time.", createdAt: now
        ))
        save()
        Task { await tick() }
    }

    func completeOnboarding() {
        run.onboarded = true
        save()
    }

    // MARK: Demo controls (eng review D5, D6, D13)

    func setClock(minutes: Int?) {
        run.clockMinutes = minutes
        save()
        Task { await tick() }
    }

    /// Adds a finished workout ending now, shaped like the real HealthKit import.
    func logWorkout() {
        let next = todayPlan.first { completion(for: $0) == nil && !isMissed($0) }
        let type = next?.slot.activityType ?? "Walking"
        let minutes = Double(next?.slot.minutes ?? 15)
        let end = now
        let workout = LoggedWorkout(Workout(
            id: "demo-\(UUID().uuidString)", activityType: type,
            start: end.addingTimeInterval(-minutes * 60), end: end,
            effort: 4, avgHeartRate: nil, source: .demo
        ))
        context.insert(workout)
        run.workouts.append(workout)
        save()
        Task { await tick() }
    }

    func switchPerson(to key: PersonaKey) {
        run.persona = key.rawValue
        clearRun(storyDay: storyDay)
        persona = Persona.load(key, storyDay: storyDay)
        save()
        Task { await tick() }
    }

    /// Clears the run: actions, logged workouts, points and the clock. Calendar
    /// cleanup joins this when calendar writes land (P0b).
    func resetDemo() {
        switchPerson(to: persona.key)
    }

    // MARK: Storage

    /// Appends an action to the log, after everything already applied.
    private func record(_ action: AgentAction) {
        let next = (run.actions.map(\.sequence).max() ?? -1) + 1
        let record = ActionRecord(action, sequence: next)
        context.insert(record)
        run.actions.append(record)
    }

    /// Drops the day's actions, logged workouts, points and clock. The person
    /// and onboarding stay.
    private func clearRun(storyDay: Date) {
        run.actions.forEach(context.delete)
        run.workouts.forEach(context.delete)
        run.actions = []
        run.workouts = []
        run.storyDay = storyDay
        run.clockMinutes = nil
        run.seenCompletions = []
        run.lastResponse = nil
        response = nil
    }

    private func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("Couldn't save the run: \(error)")
        }
    }
}
