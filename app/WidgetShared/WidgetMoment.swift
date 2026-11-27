import Foundation

/// One moment of the phone widget, made from the state the app saved (the
/// same `WatchState` the watch gets, so phone and watch never disagree).
/// Pure, so the app's tests cover the timeline the widget shows.
struct WidgetMoment: Equatable, Sendable {
    /// The widget's kind, which the app reloads when the state changes.
    static let kind = "EvergreenToday"

    var date: Date
    /// The run that needs an answer; nil once it has started.
    var run: WatchState.Run?
    /// "Sun · 12 km (was 18)", "Easy run · 30 min", "Rest day".
    var line: String
    /// "5/6", or "—" before any counted day.
    var inRange: String
    /// "5 of 6 days in range" for VoiceOver.
    var inRangeSpoken: String

    /// "In range 5/6", or "In range: —".
    var inRangeLine: String { inRange == "—" ? "In range: —" : "In range \(inRange)" }

    /// Now; the run's start, when it stops asking; and midnight, when the line
    /// rolls over to tomorrow without the app (like the watch complication).
    static func timeline(_ state: WatchState, now: Date, calendar: Calendar = .current) -> [WidgetMoment] {
        func moment(_ date: Date, line: String) -> WidgetMoment {
            WidgetMoment(date: date, run: state.run.flatMap { $0.start > date ? $0 : nil }, line: line,
                         inRange: state.inRange, inRangeSpoken: state.inRangeSpoken)
        }
        var moments = [moment(now, line: state.today)]
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        if let start = state.run?.start, start > now, midnight.map({ start < $0 }) ?? true {
            moments.append(moment(start, line: state.today))
        }
        if let midnight {
            moments.append(moment(midnight, line: state.tomorrow ?? "Open Evergreen"))
        }
        return moments
    }
}
