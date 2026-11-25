import HealthKit
import os

/// HealthKit's observer for new workouts, with background delivery (range plan
/// item 22): a finished workout wakes the app, which reads Health and shares
/// it with a buddy. Delivery is best-effort (about 4 wakes an hour at most, and
/// none after a force-quit), so the app also shares on every open. The
/// completion handler is called on every path.
enum WorkoutObserver {
    private static let log = Logger(subsystem: "com.evergreentraining.app", category: "health")
    nonisolated(unsafe) private static var started = false

    static func start() {
        guard HKHealthStore.isHealthDataAvailable(), !started else { return }
        started = true
        let store = Permissions.healthStore
        let query = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { _, completion, error in
            guard error == nil else {
                completion()
                return
            }
            // HealthKit lets the handler be called from any thread once the work is done.
            let done = UncheckedHandler(call: completion)
            Task { @MainActor in
                if let model = EvergreenAppDelegate.model {
                    await model.refreshHealth()
                    model.shareFinishedWorkouts()
                    await model.outbox.flush()
                }
                done.call()
            }
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate) { _, error in
            if let error { log.info("Background delivery not enabled: \(error.localizedDescription)") }
        }
    }
}
