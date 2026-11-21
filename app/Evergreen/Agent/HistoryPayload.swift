import Foundation

/// A real person's Apple Health history as the harness reads it
/// (harness/harness/models.py, `History`): workouts with their local UTC offset,
/// and per day the minutes asleep and resting heart rate. Sent with planner
/// requests for the person's own week; the harness keeps the latest copy under
/// the device's anonymous id.
struct HistoryPayload: Encodable, Equatable, Sendable {
    struct Session: Encodable, Equatable, Sendable {
        var activityType: String
        var start: String
        var end: String
        var avgHeartRate: Int?
        var distanceKm: Double?
        var indoor: Bool?
    }

    struct Day: Encodable, Equatable, Sendable {
        var date: String
        var sleepMin: Double?
        var restingHeartRate: Double?
    }

    var workouts: [Session]
    var daily: [Day]

    init(_ history: HealthHistory, cal: Calendar) {
        workouts = history.workouts.map {
            Session(activityType: $0.activityType, start: RecommendClient.instant($0.start, cal),
                    end: RecommendClient.instant($0.end, cal), avgHeartRate: $0.avgHeartRate,
                    distanceKm: $0.distanceKm.map { ($0 * 1000).rounded() / 1000 }, indoor: $0.indoor)
        }
        daily = history.days.map {
            Day(date: RecommendClient.day($0.date, cal), sleepMin: $0.sleepMin, restingHeartRate: $0.restingHeartRate)
        }
    }
}
