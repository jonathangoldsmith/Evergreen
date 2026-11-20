import HealthKit

/// The Health permission prompt for onboarding, shown after a one-sentence
/// explainer that matches its usage string (design D16). A denial never blocks
/// the app: the demo runs on mock data. Calendar access lives in CalendarSync.
enum Permissions {
    static let healthStore = HKHealthStore()

    static func requestHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var types: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.heartRate)]
        types.insert(HKQuantityType(.workoutEffortScore))
        types.insert(HKQuantityType(.estimatedWorkoutEffortScore))
        try? await healthStore.requestAuthorization(toShare: [], read: types)
    }
}
