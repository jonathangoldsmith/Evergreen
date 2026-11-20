import ActivityKit
import Foundation
import os

/// Starts, updates and ends the Live Activity for the next workout, all on the
/// phone (no push token). It shows from 2 hours before a workout, follows it
/// when the agent moves it, and ends with the points once it's done.
@MainActor
final class LiveActivityController {
    static let leadTime: TimeInterval = 2 * 3600
    private static let log = Logger(subsystem: "com.trackerplusplus.app", category: "liveactivity")

    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private var current: ActivityKit.Activity<WorkoutActivityAttributes>? {
        ActivityKit.Activity<WorkoutActivityAttributes>.activities.first { $0.activityState == .active }
    }

    /// The plan item the running activity follows, if any.
    var followingItemId: String? { current?.attributes.planItemId }

    /// - Parameters:
    ///   - upcoming: the next workout that isn't done or missed, with its content.
    ///   - finished: the content to end with if the followed workout is now done.
    ///   - startNow: start even if the workout is more than 2 hours away (demo control).
    func sync(
        upcoming: (item: PlanItem, state: WorkoutActivityAttributes.ContentState)?,
        finished: WorkoutActivityAttributes.ContentState?,
        storyNow: Date,
        startNow: Bool = false
    ) {
        if let activity = current {
            if let finished {
                end(activity, with: finished, after: 15 * 60)
                return
            }
            if let upcoming, upcoming.item.id == activity.attributes.planItemId {
                guard activity.content.state != upcoming.state else { return }
                let id = activity.id, state = upcoming.state
                Task { await Self.update(id: id, to: state) }
                return
            }
            end(activity, with: activity.content.state, after: 0)
        }
        guard let upcoming, isAvailable,
              startNow || upcoming.item.slot.start.timeIntervalSince(storyNow) <= Self.leadTime
        else { return }
        do {
            _ = try ActivityKit.Activity<WorkoutActivityAttributes>.request(
                attributes: WorkoutActivityAttributes(planItemId: upcoming.item.id),
                content: ActivityContent(state: upcoming.state, staleDate: nil),
                pushType: nil
            )
            Self.log.info("Started a Live Activity for \(upcoming.item.id)")
        } catch {
            Self.log.error("Couldn't start a Live Activity: \(error.localizedDescription)")
        }
    }

    /// Reset demo: no activity left over from the last rehearsal.
    func endAll() {
        for activity in ActivityKit.Activity<WorkoutActivityAttributes>.activities {
            end(activity, with: activity.content.state, after: 0)
        }
    }

    private func end(
        _ activity: ActivityKit.Activity<WorkoutActivityAttributes>,
        with state: WorkoutActivityAttributes.ContentState,
        after seconds: TimeInterval
    ) {
        let id = activity.id
        Task { await Self.end(id: id, with: state, after: seconds) }
    }

    // ActivityKit's Activity isn't Sendable, so tasks carry its id and look it
    // up again off the main actor.

    private nonisolated static func update(id: String, to state: WorkoutActivityAttributes.ContentState) async {
        guard let activity = ActivityKit.Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    private nonisolated static func end(
        id: String, with state: WorkoutActivityAttributes.ContentState, after seconds: TimeInterval
    ) async {
        guard let activity = ActivityKit.Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(ActivityContent(state: state, staleDate: nil),
                           dismissalPolicy: seconds == 0 ? .immediate : .after(.now.addingTimeInterval(seconds)))
    }
}
