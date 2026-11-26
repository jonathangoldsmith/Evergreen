import WidgetKit

/// One moment of the complication: the week's range and the day's run.
struct RangeEntry: TimelineEntry {
    let date: Date
    let inRange: String
    let inRangeSpoken: String
    let line: String
}
