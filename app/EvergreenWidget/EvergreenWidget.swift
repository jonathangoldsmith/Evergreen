import SwiftUI
import WidgetKit

/// The phone widget (TODOS "Readiness, range, sleep and widgets", item 1):
/// text only, never a ring or chart (DESIGN.md). The Lock Screen shows today's
/// line and the week in range; the Home Screen medium size also asks the run
/// question the watch asks, and its buttons open Evergreen with the answer.
@main
struct EvergreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetMoment.kind, provider: TodayProvider()) { moment in
            TodayWidgetView(moment: moment, token: WidgetLink.token())
                .containerBackground(for: .widget) { Color(.card) }
        }
        .configurationDisplayName("Evergreen")
        .description("Today's workout and your week in range.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

extension WidgetMoment: TimelineEntry {}

/// Reads the state the app saved in the App Group. The app reloads the widget
/// whenever that state changes, so the timeline never asks for a refresh.
struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetMoment {
        WidgetMoment(date: Date(), run: nil, line: "Easy run · 30 min", inRange: "5/6", inRangeSpoken: "5 of 6 days in range")
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetMoment) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : moments().first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetMoment>) -> Void) {
        completion(Timeline(entries: moments(), policy: .never))
    }

    private func moments() -> [WidgetMoment] {
        WidgetMoment.timeline(WatchStateStore.load() ?? .empty, now: Date())
    }
}
