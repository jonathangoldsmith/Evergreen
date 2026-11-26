import SwiftUI
import WidgetKit

/// The watch complications (design decision 18): text only, never a ring.
/// Circular: "5/6" days in range. Rectangular: today's run and its state.
@main
struct EvergreenComplications: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EvergreenRange", provider: RangeProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Evergreen")
        .description("Days in range this week, and today's run.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
