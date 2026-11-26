import WidgetKit

/// Reads the state the watch app saved in the App Group. Two entries: now,
/// and midnight with tomorrow's line, so "today's run" rolls over without the
/// phone (eng re-run outside voice #6).
struct RangeProvider: TimelineProvider {
    func placeholder(in context: Context) -> RangeEntry {
        RangeEntry(date: Date(), inRange: "5/6", inRangeSpoken: "5 of 6 days in range", line: "Sun · 12 km (was 18)")
    }

    func getSnapshot(in context: Context, completion: @escaping (RangeEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries().first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RangeEntry>) -> Void) {
        completion(Timeline(entries: entries(), policy: .never))
    }

    private func entries(now: Date = Date()) -> [RangeEntry] {
        let state = WatchStateStore.load() ?? .empty
        var entries = [RangeEntry(date: now, inRange: state.inRange, inRangeSpoken: state.inRangeSpoken, line: state.today)]
        if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) {
            entries.append(RangeEntry(date: midnight, inRange: state.inRange, inRangeSpoken: state.inRangeSpoken,
                                      line: state.tomorrow ?? "Open Evergreen"))
        }
        return entries
    }
}
