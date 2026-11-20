import EventKit
import HealthKit

/// Permission prompts for onboarding. Each is shown after a one-sentence
/// explainer that matches its usage string (design D16). A denial never blocks
/// the app: the demo runs on mock data, and the plan stays in the app without
/// calendar access (design D5).
enum Permissions {
    static let healthStore = HKHealthStore()

    static func requestHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var types: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.heartRate)]
        types.insert(HKQuantityType(.workoutEffortScore))
        types.insert(HKQuantityType(.estimatedWorkoutEffortScore))
        try? await healthStore.requestAuthorization(toShare: [], read: types)
    }

    /// Full access, because slot defense has to read other calendars (eng review
    /// Section 1); write-only access can't see the meeting that lands on a workout.
    static func requestCalendar() async {
        _ = try? await EKEventStore().requestFullAccessToEvents()
    }
}
