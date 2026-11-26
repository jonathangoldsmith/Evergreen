import SwiftUI
import WidgetKit

/// Text only, with a VoiceOver label (design decisions 16 and 18).
struct ComplicationView: View {
    let entry: RangeEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Text(entry.inRange)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .minimumScaleFactor(0.6)
                .accessibilityLabel(entry.inRangeSpoken)
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text("Evergreen")
                    .font(.headline)
                    .widgetAccentable()
                Text(entry.line)
                    .font(.body)
                    .lineLimit(2)
                Text(entry.inRange == "—" ? "In range: —" : "In range \(entry.inRange)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Evergreen. \(entry.line). \(entry.inRangeSpoken).")
        }
    }
}
