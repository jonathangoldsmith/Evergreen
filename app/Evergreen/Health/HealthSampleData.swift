#if DEBUG
import HealthKit

/// Demo control, Debug builds only: fills Apple Health with a month of sample
/// data (Jordan's mock workouts, nights of sleep, resting heart rate), so the
/// real Apple Health path can be tried on a simulator that has none. It writes
/// real HealthKit samples; the app then reads them like anyone's.
enum HealthSampleData {
    static let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.heartRate),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.distanceWalkingRunning),
        HKCategoryType(.sleepAnalysis),
    ]

    /// Asks to write, then adds the samples. Returns how many workouts it added.
    static func fill(storyDay: Date, calendar: Calendar = .current) async throws -> Int {
        let store = Permissions.healthStore
        try await store.requestAuthorization(toShare: shareTypes, read: HealthReader.readTypes)
        let mock = Persona.load(.jordan, storyDay: storyDay, calendar: calendar).workouts
        let bpm = HKUnit.count().unitDivided(by: .minute())
        var added = 0
        for w in mock where w.end < Date() {
            let config = HKWorkoutConfiguration()
            config.activityType = type(w.activityType)
            let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
            try await builder.beginCollection(at: w.start)
            var samples: [HKSample] = []
            if let rate = w.avgHeartRate {
                samples.append(HKQuantitySample(type: HKQuantityType(.heartRate), quantity: HKQuantity(unit: bpm, doubleValue: Double(rate)),
                                                start: w.start, end: w.end))
            }
            if w.activityType == "Running" || w.activityType == "Walking" {
                // About 5:35/km running, 11:00/km walking.
                let km = w.minutes / (w.activityType == "Running" ? 5.6 : 11)
                samples.append(HKQuantitySample(type: HKQuantityType(.distanceWalkingRunning),
                                                quantity: HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: km),
                                                start: w.start, end: w.end))
            }
            if !samples.isEmpty { try await builder.addSamples(samples) }
            try await builder.endCollection(at: w.end)
            _ = try await builder.finishWorkout()
            added += 1
        }
        try await store.save(nights(storyDay: storyDay, calendar: calendar))
        return added
    }

    /// 28 nights of about 7½ hours and a resting heart rate around 49, and
    /// 60 mornings of HRV around 62 ms.
    private static func nights(storyDay: Date, calendar: Calendar) -> [HKSample] {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        var samples: [HKSample] = []
        for back in 1...60 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: storyDay),
                  let morning = calendar.date(bySettingHour: 7, minute: 5, second: 0, of: day) else { continue }
            samples.append(HKQuantitySample(type: HKQuantityType(.heartRateVariabilitySDNN),
                                            quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: Double(58 + back % 9)),
                                            start: morning, end: morning))
        }
        for back in 1...28 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: storyDay),
                  let bed = calendar.date(bySettingHour: 23, minute: back % 3 * 10, second: 0,
                                          of: calendar.date(byAdding: .day, value: -1, to: day) ?? day),
                  let wake = calendar.date(bySettingHour: 6, minute: 30 + back % 4 * 5, second: 0, of: day),
                  let morning = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day)
            else { continue }
            samples.append(HKCategorySample(type: HKCategoryType(.sleepAnalysis),
                                            value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: bed, end: wake))
            samples.append(HKQuantitySample(type: HKQuantityType(.restingHeartRate),
                                            quantity: HKQuantity(unit: bpm, doubleValue: Double(48 + back % 3)),
                                            start: morning, end: morning))
        }
        return samples
    }

    private static func type(_ name: String) -> HKWorkoutActivityType {
        switch name {
        case "Running": .running
        case "Walking": .walking
        case "Cycling": .cycling
        case "Elliptical": .elliptical
        case "FunctionalStrengthTraining": .functionalStrengthTraining
        case "TraditionalStrengthTraining": .traditionalStrengthTraining
        case "Yoga": .yoga
        case "Swimming": .swimming
        default: .other
        }
    }
}
#endif
