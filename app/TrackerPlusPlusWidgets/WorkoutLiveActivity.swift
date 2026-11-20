import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen and Dynamic Island for the next workout. DESIGN.md: the accent
/// marks the agent's work, progress is a sentence, no rings or confetti.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenView(state: context.state)
                .activityBackgroundTint(Color(.surface))
                .activitySystemActionForegroundColor(Color(.text))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.startText, systemImage: context.state.symbol)
                        .font(.headline)
                        .foregroundStyle(Color(.accent))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutTimeText(state: context.state)
                        .font(.headline.monospacedDigit())
                        .frame(maxWidth: 80, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.title).font(.headline)
                        Text(context.state.note).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.state.symbol)
                    .foregroundStyle(Color(.accent))
            } compactTrailing: {
                WorkoutTimeText(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: context.state.phase == .done ? "checkmark" : context.state.symbol)
                    .foregroundStyle(Color(.accent))
            }
            .keylineTint(Color(.accent))
        }
    }
}
