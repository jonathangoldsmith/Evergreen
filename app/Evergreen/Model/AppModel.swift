import AmplitudeSwift
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
    /// Whether the plan is also on the Evergreen calendar.
    private(set) var calendarAccess: CalendarAccess

    private let calendar = Calendar.current
    @ObservationIgnored private let calendarSync = CalendarSync()
    @ObservationIgnored private let notifier = Notifier()
    /// Tony's memory bundle in JavaScriptCore; nil if it doesn't load.
    @ObservationIgnored private let memory = MemoryEngine.standard()
    /// The app's Amplitude client, made once in the app entry; nil without a key.
    @ObservationIgnored private let amplitude: Amplitude?
    /// The last memory sync, for the demo controls.
    private(set) var memoryReport: MemoryEngine.Report?
    /// Events Amplitude accepted since launch.
    private(set) var amplitudeSent = 0
    /// Whether this phone's owner has passed the Persona identity check. Kept
    /// per install, so it survives switching demo people; until it's true the
    /// agent buys nothing on its own and Order it asks for the check first.
    private(set) var identityVerified = UserDefaults.standard.bool(forKey: "identity_verified")
    /// Whether an Amplitude key was built in (app/Secrets.xcconfig).
    var amplitudeOn: Bool { amplitude != nil }
    /// Whether notifications are allowed, for onboarding and the demo controls.
    private(set) var notificationAccess: NotificationAccess = .notAsked

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

    init(context: ModelContext, amplitude: Amplitude? = nil) {
        self.context = context
        self.amplitude = amplitude
        let today = Calendar.current.startOfDay(for: Date())
        let saved = (try? context.fetch(FetchDescriptor<Run>()))?.first
        let run = saved ?? Run(persona: .jordan, storyDay: today)
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

    // MARK: Harness planner (read-only)

    /// Whether the harness planner is set up (it shares the shoe pick's secret).
    var plannerAvailable: Bool { PlannerClient.configured() != nil }

    /// What the planner needs about this person now: the demo clock, the shoe
    /// wear and race from the demo, the new pair's arrival once one is ordered,
    /// and the busy times on their other calendars.
    func plannerRequest() -> PlannerClient.Request {
        PlannerClient.request(
            persona: persona.key.rawValue, now: now, demo: run.demo, newPairArrives: newShoesArrive,
            busy: calendarSync.busyTimes(from: storyDay), cal: calendar
        )
    }

    /// When the ordered pair arrives; nil before Order it or after Cancel order.
    private var newShoesArrive: Date? {
        let shoes = Set(appliedActions.compactMap(\.purchaseId).filter { $0.hasPrefix("shoes-") })
        return shoes.compactMap(purchaseState).first { $0.status == .bought }?.options.first?.arrives
    }

    /// The person's standing spending rule (premise 2), set once in onboarding.
    nonisolated static let mandate = [
        Mandate(id: "ask-first", text: "Always check with me before buying anything.", category: .any, maxAutoCents: 0),
    ]

    func isUndone(_ action: AgentAction) -> Bool { undoneIds.contains(action.id) }

    func completion(for item: PlanItem) -> Completion? {
        response?.completions.first { $0.planItemId == item.id }
    }

    func isMissed(_ item: PlanItem) -> Bool {
        completion(for: item) == nil && item.slot.end.addingTimeInterval(StandInAgent.grace) <= now
    }

    // MARK: Agent

    /// Ticks now, then every minute while the app is on screen, so a window that
    /// passes with the app open is still noticed.
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
            visits: run.visits,
            identityVerified: identityVerified
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
        let sink = amplitude.map(AmplitudeSink.init)
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
            announceMove(action)
        }
        self.response = response
        run.lastResponse = try? JSONEncoder.contract.encode(response)
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
        amplitude?.track(eventType: "Purchase Approved")
        save()
        Task { await tick() }
    }

    /// Persona finished the inquiry: purchases may go ahead, and the agent may
    /// buy under the person's rule from now on.
    func identityVerified(inquiryId: String) {
        identityVerified = true
        UserDefaults.standard.set(true, forKey: "identity_verified")
        UserDefaults.standard.set(inquiryId, forKey: "persona_inquiry_id")
    }

    /// Demo control: back to unverified, so the next purchase asks for the check again.
    func forgetVerification() {
        identityVerified = false
        UserDefaults.standard.removeObject(forKey: "identity_verified")
        UserDefaults.standard.removeObject(forKey: "persona_inquiry_id")
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
        await scheduleNotifications()
    }

    private func scheduleNotifications() async {
        let upcoming = plan.filter { completion(for: $0) == nil }
        await notifier.scheduleReminders(for: upcoming)
    }

    /// Starts clean: a reinstall keeps calendar events, so clear the plan and
    /// any demo meeting a previous install left before the first plan syncs.
    func completeOnboarding() {
        calendarSync.removeAllEvents(around: storyDay)
        run.onboarded = true
        save()
    }

    // MARK: Demo controls

    /// The test meeting's title, kept so the move notification can name it.
    /// Calendar sync passes only busy times to the agent, never titles.
    @ObservationIgnored private var testMeeting: (title: String, start: Date)?

    /// The workout "Add a meeting" lands on: the next one still ahead.
    var nextUpcomingWorkout: PlanItem? {
        plan.first { $0.slot.start > now && completion(for: $0) == nil }
    }

    /// Puts a 1-hour "Team sync" on the person's calendar starting 15 minutes
    /// before that workout. The calendar change triggers the tick that moves it.
    func addTestMeeting() {
        guard let item = nextUpcomingWorkout else { return }
        let start = item.slot.start.addingTimeInterval(-15 * 60)
        testMeeting = (CalendarSync.testMeetingTitle, start)
        calendarSync.addTestMeeting(start: start, end: start.addingTimeInterval(60 * 60))
    }

    /// When the agent moves a workout off a meeting, says so as a notification:
    /// "Team sync landed on your run … I moved it to 6:45 PM."
    private func announceMove(_ action: AgentAction) {
        guard action.id.hasPrefix("defend-"), let before = action.before, let after = action.after else { return }
        let meeting = testMeeting.flatMap { $0.start < before.end ? $0 : nil }
        let copy = NotificationCopy.moved(before: before, after: after, meeting: meeting)
        Task { await notifier.send(copy, id: action.id) }
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

    /// The rain the day-pass rule reacts to: the start of tomorrow's first
    /// outdoor workout (Jordan's Saturday 8:30 AM long run).
    var rainTime: Date? {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: storyDay) ?? storyDay
        return plan.first {
            StandInAgent.outdoorTypes.contains($0.slot.activityType)
                && calendar.isDate($0.slot.start, inSameDayAs: tomorrow) && $0.slot.start > now
        }?.slot.start
    }

    /// Race day in the shoes demo.
    var raceDate: Date? { run.demo?.raceDate }

    /// Demo control: rain on Saturday's run; the agent suggests a day pass.
    func forecastRain() {
        guard let rainTime else { return }
        var demo = run.demo ?? DemoConditions()
        demo.rainAt = rainTime
        demo.forecastClear = false
        run.demo = demo
        save()
        Task { await tick() }
    }

    // MARK: Demo beats
    // Each beat starts from a clean run for Jordan, so the beats can be shown
    // in any order and an earlier one never covers the next.

    /// The plan: "Let's do three workouts this week."
    func showPlan() {
        resetDemo()
    }

    /// Friday, 4 PM: a "Team sync" lands on tonight's 6 PM run; Evergreen moves the
    /// run and sends a notification about it.
    func showMovedDemo() {
        calendarSync.removeAllEvents(around: storyDay)
        switchPerson(to: .jordan, clock: 16 * 60)
        addTestMeeting()
    }

    /// Rain on Saturday's run: the agent suggests a gym day pass.
    func showRainDemo() {
        resetDemo()
        forecastRain()
    }

    /// Jordan's shoes near 400 miles with a race in 9 days. His 30-day history
    /// adds about 125 miles to the 267 already on the pair.
    func showShoesDemo() {
        calendarSync.removeAllEvents(around: storyDay)
        switchPerson(to: .jordan) { [calendar, storyDay] person in
            DemoConditions(
                shoesBoughtOn: person.historyStart,
                shoesStartMiles: 267,
                raceDate: calendar.date(byAdding: .day, value: 9, to: storyDay)
            )
        }
    }

    /// Clears the run (actions, logged workouts, the clock), the Evergreen
    /// calendar and the test meeting.
    func resetDemo() {
        calendarSync.removeAllEvents(around: storyDay)
        testMeeting = nil
        switchPerson(to: .jordan)
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
    /// Evergreen calendar in line with the plan. Every change to the run
    /// goes through here.
    private func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("Couldn't save the run: \(error)")
        }
        refreshFromStore()
        syncCalendar()
        Task { await scheduleNotifications() }
    }

    private func refreshFromStore() {
        let records = run.actions.sorted { $0.sequence < $1.sequence }
        appliedActions = records.map(\.action)
        undoneIds = Set(records.filter(\.undone).map(\.actionId))
        loggedWorkouts = run.workouts.map(\.workout).sorted { $0.start < $1.start }
    }

    /// Puts the plan on the calendar: the pinned week and the agent's moves,
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
