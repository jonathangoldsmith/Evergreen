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
    /// Whether the plan is also on the TrackerPlusPlus calendar.
    private(set) var calendarAccess: CalendarAccess
    /// Set when a workout finishes a plan item; drives the Done sheet.
    var celebration: Completion?

    private let calendar = Calendar.current
    @ObservationIgnored private let calendarSync = CalendarSync()
    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private let liveActivity = LiveActivityController()
    /// Tony's memory bundle in JavaScriptCore; nil if it doesn't load.
    @ObservationIgnored private let memory = MemoryEngine.standard()
    /// The last memory sync, for the demo controls.
    private(set) var memoryReport: MemoryEngine.Report?
    /// Events Amplitude accepted since launch.
    private(set) var amplitudeSent = 0
    /// Whether an Amplitude key is set in iOS Settings.
    private(set) var amplitudeOn = false
    /// Whether notifications are allowed, for onboarding and the demo controls.
    private(set) var notificationAccess: NotificationAccess = .notAsked
    private(set) var gymAlertsOn = false

    // Copied out of SwiftData on every save, so views depend on this class
    // rather than on individual records. Without the copy, undoing a move
    // changed the stored record but Today didn't redraw until the next reply
    // from the agent differed from the last one.

    /// Every applied action, oldest first, undone ones included.
    private(set) var appliedActions: [AgentAction] = []
    private(set) var undoneIds: Set<String> = []
    private(set) var loggedWorkouts: [Workout] = []
    /// Counts ticks so only the newest one's answer is applied. Ticks overlap
    /// (a clock change right after a logged workout), and a slow harness reply
    /// to an older snapshot must not replace a newer one.
    @ObservationIgnored private var latestTick = 0
    /// Waits for a burst of calendar changes to settle before ticking.
    @ObservationIgnored private var calendarChangeTask: Task<Void, Never>?

    init(context: ModelContext) {
        self.context = context
        let today = Calendar.current.startOfDay(for: Date())
        let saved = (try? context.fetch(FetchDescriptor<Run>()))?.first
        let run = saved ?? Run(persona: .sam, storyDay: today)
        if saved == nil { context.insert(run) }
        self.run = run
        calendarAccess = calendarSync.access
        persona = Persona.load(run.personaKey, storyDay: today)
        response = nil
        if run.storyDay != today {
            // A new day is a new story day: keep the person and onboarding, drop the run.
            clearRun(storyDay: today)
        } else {
            response = run.lastResponse.flatMap { try? JSONDecoder.contract.decode(TickResponse.self, from: $0) }
        }
        save()
        calendarSync.onChange = { [weak self] in self?.calendarChanged() }
        notifier.onOpen = { [weak self] in Task { await self?.tick() } }
        Task { await refreshNotifications() }
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
            case .move, .shrink, .purchase, .cancelPurchase:
                // A day pass moves the workout to the gym; its cancel moves it back.
                if let index = items.firstIndex(where: { $0.id == id }) { items[index].slot = after }
            case .addWorkout:
                // Break-in runs leave the plan when their order is cancelled.
                if let purchaseId = action.purchaseId, purchaseState(purchaseId)?.status == .cancelled { continue }
                items.append(PlanItem(id: id, slot: after, points: action.points ?? StandInAgent.basePoints, source: .plan))
            case .note, .purchaseOutcome:
                break
            }
        }
        return items.sorted { $0.slot.start < $1.slot.start }
    }

    var todayPlan: [PlanItem] { plan.filter { calendar.isDate($0.slot.start, inSameDayAs: storyDay) } }

    var workouts: [Workout] {
        persona.workouts + loggedWorkouts
    }

    /// Every applied action, oldest first, undone ones included.

    /// Newest first.
    var feed: [AgentAction] { appliedActions.reversed() }

    /// The one card on Today: the latest action that's still in effect.
    var latestAction: AgentAction? { feed.first { !isUndone($0) } }

    /// A purchase as of its newest action still in effect. Each state change is
    /// its own action (the phone ignores known ids), so the trail folds here.
    func purchaseState(_ purchaseId: String) -> Purchase? {
        appliedActions.last { $0.purchaseId == purchaseId && $0.purchase != nil && !isUndone($0) }?.purchase
    }

    /// Every action in one purchase's trail, oldest first.
    func purchaseTrail(_ purchaseId: String) -> [AgentAction] {
        appliedActions.filter { $0.purchaseId == purchaseId }
    }

    /// The person's standing spending rule (premise 2), set once in onboarding.
    nonisolated static let mandate = [
        Mandate(id: "ask-first", text: "Ask me before buying anything else.", category: .any, maxAutoCents: 0),
        Mandate(id: "day-pass", text: "Day passes up to $20: book it, tell me after.", category: .dayPass, maxAutoCents: 2000),
    ]

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
            undoneActionIds: appliedActions.map(\.id).filter(undoneIds.contains),
            busy: calendarSync.busyTimes(from: storyDay),
            mandate: Self.mandate,
            approvedPurchaseIds: run.approvedPurchaseIds,
            demo: run.demo,
            visits: run.visits
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
        await syncMemory()
    }

    /// Rolls the person's memory and sends its staged events to Amplitude when
    /// a key is set (memory-agent/docs/AMPLITUDE.md). Never blocks the agent.
    func syncMemory() async {
        guard let memory else { return }
        let sink = AmplitudeSink.configured()
        amplitudeOn = sink != nil
        let input = MemoryInput(
            personaKey: persona.key.rawValue, historyStart: persona.historyStart,
            now: now, workouts: workouts, calendar: calendar
        )
        let report = await memory.sync(input, sink: sink)
        amplitudeSent += report.sent
        memoryReport = report
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

    /// "Order it" on a purchase that's waiting for the person.
    func approvePurchase(_ purchaseId: String) {
        guard !run.approvedPurchaseIds.contains(purchaseId) else { return }
        run.approvedPurchaseIds.append(purchaseId)
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

    /// Onboarding's calendar step, and "Turn on Calendar" before anyone has
    /// been asked. Puts the plan on the calendar if access is granted.
    func requestCalendarAccess() async {
        await calendarSync.requestAccess()
        syncCalendar()
    }

    /// Something changed on the phone's calendars, maybe a meeting on a
    /// workout (slot defense). The app's own writes land here too; a tick that
    /// changes nothing writes nothing, so this settles.
    private func calendarChanged() {
        calendarChangeTask?.cancel()
        calendarChangeTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await tick()
        }
    }

    // MARK: Notifications and Live Activity

    /// The next workout that isn't done or missed yet.
    var nextWorkout: PlanItem? {
        plan.first { completion(for: $0) == nil && !isMissed($0) && $0.slot.end > now }
    }

    /// Onboarding's notifications step.
    func requestNotificationAccess() async {
        await notifier.requestAccess()
        await refreshNotifications()
    }

    func refreshNotifications() async {
        await notifier.refreshAccess()
        notificationAccess = notifier.access
        gymAlertsOn = notifier.gymAlertsOn
        await scheduleNotifications()
    }

    /// Demo control: what the agent last did, as a notification in 5 seconds.
    func sendTestNotification() {
        let latest = latestAction.flatMap { $0.kind == .note ? nil : $0 }
        Task { await notifier.sendTestNotification(for: latest, fallback: nextWorkout, now: now, after: 5) }
    }

    /// Demo control: what arriving at or leaving the gym sends.
    func sendGymNotification(arriving: Bool) {
        Task { await notifier.sendGymNotification(arriving: arriving, next: nextWorkout) }
    }

    func setGymAlerts(_ on: Bool) async {
        if on {
            if notificationAccess != .on { await requestNotificationAccess() }
            await notifier.enableGymAlerts(next: nextWorkout)
        } else {
            notifier.disableGymAlerts()
        }
        gymAlertsOn = notifier.gymAlertsOn
    }

    /// Demo control: show the Live Activity now, however far off the workout is.
    func startLiveActivity() {
        syncLiveActivity(startNow: true)
    }

    var liveActivityAvailable: Bool { liveActivity.isAvailable }

    private func scheduleNotifications() async {
        let upcoming = plan.filter { completion(for: $0) == nil }
        await notifier.scheduleReminders(for: upcoming)
        await notifier.scheduleGymAlerts(next: nextWorkout)
    }

    private func syncLiveActivity(startNow: Bool = false) {
        var finished: WorkoutActivityAttributes.ContentState?
        if let id = liveActivity.followingItemId,
           let item = plan.first(where: { $0.id == id }),
           let done = completion(for: item) {
            var state = activityState(for: item)
            state.phase = .done
            state.points = done.points
            state.note = NotificationCopy.activityDone(points: done.points)
            finished = state
        }
        liveActivity.sync(
            upcoming: nextWorkout.map { ($0, activityState(for: $0)) },
            finished: finished,
            storyNow: now,
            startNow: startNow
        )
    }

    private func activityState(for item: PlanItem) -> WorkoutActivityAttributes.ContentState {
        let movedByAgent = appliedActions.contains {
            $0.planItemId == item.id && $0.id.hasPrefix("defend-") && !isUndone($0)
        }
        return WorkoutActivityAttributes.ContentState(
            phase: .upcoming,
            title: item.source == .comeback
                ? "Comeback \(Activity.noun(item.slot.activityType))"
                : Activity.title(item.slot.activityType),
            symbol: Activity.symbol(item.slot.activityType),
            startText: item.slot.start.clock,
            minutes: item.slot.minutes,
            points: item.points,
            isComeback: item.source == .comeback,
            // Shifted by the demo clock, so the countdown matches the story time.
            countdownTo: Date.now.addingTimeInterval(item.slot.start.timeIntervalSince(now)),
            note: NotificationCopy.activityNote(item, movedByAgent: movedByAgent)
        )
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

    /// The workout "Add a meeting" lands on: the first one after the story day,
    /// so the demo can show defense before the miss (demo script step 3).
    var nextDaysFirstWorkout: PlanItem? {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: storyDay) ?? storyDay
        return plan.first { $0.slot.start >= tomorrow && completion(for: $0) == nil }
    }

    /// Puts a 1-hour test meeting on the person's calendar starting 15 minutes
    /// before that workout. The calendar change triggers the tick that moves it.
    func addTestMeeting() {
        guard let item = nextDaysFirstWorkout else { return }
        let start = item.slot.start.addingTimeInterval(-15 * 60)
        calendarSync.addTestMeeting(start: start, end: start.addingTimeInterval(60 * 60))
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

    func switchPerson(to key: PersonaKey, clock: Int? = nil, demo: ((Persona) -> DemoConditions)? = nil) {
        run.persona = key.rawValue
        clearRun(storyDay: storyDay)
        persona = Persona.load(key, storyDay: storyDay)
        run.clockMinutes = clock
        run.demo = demo?(persona)
        save()
        Task { await tick() }
    }

    /// Demo preset: Sam at 1:30 PM, so the missed lunch walk already has its
    /// 6:30 PM comeback for the rain beat.
    func showRainDemo() {
        switchPerson(to: .sam, clock: 13 * 60 + 30)
    }

    /// The 6:30 PM rain the day-pass rule reacts to.
    var rainTime: Date { calendar.date(bySettingHour: 18, minute: 30, second: 0, of: storyDay) ?? storyDay }

    /// Demo control: rain at 6:30 PM; the agent may buy a day pass.
    func forecastRain() {
        var demo = run.demo ?? DemoConditions()
        demo.rainAt = rainTime
        demo.forecastClear = false
        run.demo = demo
        save()
        Task { await tick() }
    }

    /// Demo control: the forecast clears; the agent may cancel its own pass.
    func clearForecast() {
        var demo = run.demo ?? DemoConditions()
        demo.forecastClear = true
        run.demo = demo
        save()
        Task { await tick() }
    }

    var rainForecast: Bool { run.demo?.rainAt != nil && run.demo?.forecastClear == false }

    /// Demo control: arrive at the gym now. Records the visit the day-pass
    /// outcome reads, and sends the arrival notification when allowed. The
    /// real geofence only notifies; it runs no app code.
    func arriveAtGym() {
        run.visits.append(Visit(place: StandInAgent.gym, at: now))
        save()
        if notificationAccess == .on { sendGymNotification(arriving: true) }
        Task { await tick() }
    }

    /// Demo preset: Jordan's shoes near 400 miles with a race in 9 days. His
    /// 30-day history adds about 125 miles to the 267 already on the pair.
    func showShoesDemo() {
        switchPerson(to: .jordan) { [calendar, storyDay] person in
            DemoConditions(
                shoesBoughtOn: person.historyStart,
                shoesStartMiles: 267,
                raceDate: calendar.date(byAdding: .day, value: 9, to: storyDay)
            )
        }
    }

    /// Clears the run: actions, logged workouts, points and the clock. Calendar
    /// cleanup joins this when calendar writes land (P0b).
    func resetDemo() {
        calendarSync.removeAllEvents(around: storyDay)
        liveActivity.endAll()
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
        run.approvedPurchaseIds = []
        run.demo = nil
        run.visits = []
        response = nil
    }

    /// Saves the run, refreshes what views read, then brings the
    /// TrackerPlusPlus calendar in line with the plan. Every change to the run
    /// goes through here.
    private func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("Couldn't save the run: \(error)")
        }
        refreshFromStore()
        syncCalendar()
        syncLiveActivity()
        Task { await scheduleNotifications() }
    }

    private func refreshFromStore() {
        let records = run.actions.sorted { $0.sequence < $1.sequence }
        appliedActions = records.map(\.action)
        undoneIds = Set(records.filter(\.undone).map(\.actionId))
        loggedWorkouts = run.workouts.map(\.workout).sorted { $0.start < $1.start }
    }

    /// Puts the plan on the calendar: the pinned week, comebacks and moves,
    /// minus anything undone. Without access the plan stays in the app.
    private func syncCalendar() {
        calendarAccess = calendarSync.access
        guard calendarAccess == .on else { return }
        var reasons: [String: String] = [:]
        for action in appliedActions where !isUndone(action) {
            if let id = action.planItemId { reasons[id] = action.reason }
        }
        let entries = CalendarEntry.entries(for: plan, reasons: reasons, storyDay: storyDay, calendar: calendar)
        calendarSync.sync(entries, from: storyDay)
    }
}
