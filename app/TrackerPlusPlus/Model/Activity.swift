import Foundation

/// Display names and SF Symbols for HealthKit activity types.
enum Activity {
    static func noun(_ type: String) -> String {
        switch type {
        case "Walking": "walk"
        case "Running": "run"
        case "Elliptical": "elliptical session"
        case "TraditionalStrengthTraining", "FunctionalStrengthTraining": "strength session"
        case "Yoga": "yoga session"
        case "Cycling": "ride"
        case "Swimming": "swim"
        default: "workout"
        }
    }

    static func title(_ type: String) -> String {
        switch type {
        case "Walking": "Walk"
        case "Running": "Run"
        case "Elliptical": "Elliptical"
        case "TraditionalStrengthTraining", "FunctionalStrengthTraining": "Strength"
        case "Yoga": "Yoga"
        case "Cycling": "Ride"
        case "Swimming": "Swim"
        default: "Workout"
        }
    }

    static func symbol(_ type: String) -> String {
        switch type {
        case "Walking": "figure.walk"
        case "Running": "figure.run"
        case "Elliptical": "figure.elliptical"
        case "TraditionalStrengthTraining", "FunctionalStrengthTraining": "dumbbell"
        case "Yoga": "figure.yoga"
        case "Cycling": "figure.outdoor.cycle"
        case "Swimming": "figure.pool.swim"
        default: "figure.mixed.cardio"
        }
    }
}

extension Date {
    /// "12:00 PM"
    var clock: String { formatted(date: .omitted, time: .shortened) }
}

extension Slot {
    /// "12:00 PM, 30 min"
    var summary: String { "\(start.clock), \(minutes) min" }
}
