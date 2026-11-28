import SwiftUI
import WidgetKit

/// Text only, with VoiceOver labels (DESIGN.md: progress is a sentence, never
/// a ring or chart). The accent is for the agent's action only: the primary
/// answer and what was decided. Answers follow the watch's order: what was
/// decided, then the swap question, then the morning check.
struct TodayWidgetView: View {
    let moment: WidgetMoment
    let token: String?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(WidgetLink.today.url(token: token))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Text(moment.line)
        case .accessoryCircular:
            Text(moment.inRange)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .minimumScaleFactor(0.6)
                .accessibilityLabel(moment.inRangeSpoken)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Evergreen")
                    .font(.headline)
                    .widgetAccentable()
                Text(moment.line)
                    .font(.body)
                    .lineLimit(2)
                Text(moment.inRangeLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Evergreen. \(moment.line). \(moment.inRangeSpoken).")
        case .systemSmall:
            small
        default:
            medium
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            Text(moment.run?.decided ?? moment.line)
                .font(.headline)
                .foregroundStyle(moment.run?.decided == nil ? Color(.text) : Color(.accent))
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            Text(moment.inRangeLine)
                .font(.footnote)
                .foregroundStyle(Color(.textMuted))
                .accessibilityLabel(moment.inRangeSpoken)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                header
                Spacer()
                Text(moment.inRangeLine)
                    .font(.footnote)
                    .foregroundStyle(Color(.textMuted))
                    .accessibilityLabel(moment.inRangeSpoken)
            }
            if let run = moment.run, let decided = run.decided {
                runLine(run)
                Text(decided)
                    .font(.headline)
                    .foregroundStyle(Color(.accent))
                    .widgetAccentable()
                Spacer(minLength: 0)
            } else if let run = moment.run, let question = run.question {
                Text(question)
                    .font(.headline)
                    .foregroundStyle(Color(.text))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    answer(run.acceptLabel ?? "Make it shorter", .accept, run, primary: true)
                    answer(run.keepLabel ?? "Keep it", .keep, run)
                }
            } else if let run = moment.run, run.asksCheck {
                runLine(run)
                Text("How do your legs feel?")
                    .font(.headline)
                    .foregroundStyle(Color(.text))
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    answer("Fresh", .fresh, run)
                    answer("Tired", .tired, run)
                    answer("Sore", .sore, run)
                }
            } else {
                Spacer(minLength: 0)
                Text(moment.line)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(.text))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var header: some View {
        Text("Evergreen")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(.textMuted))
    }

    private func runLine(_ run: WatchState.Run) -> some View {
        Text(run.line)
            .font(.footnote)
            .foregroundStyle(Color(.textMuted))
            .lineLimit(1)
    }

    /// Primary is solid accent, the rest a 1px rule (DESIGN.md buttons), 44pt tall.
    private func answer(_ label: String, _ kind: WatchAnswer.Kind, _ run: WatchState.Run, primary: Bool = false) -> some View {
        Link(destination: WidgetLink.answer(runKey: run.key, kind: kind).url(token: token)) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(primary ? Color(.onAccent) : Color(.text))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(primary ? Color(.accent) : Color.clear)
                }
                .overlay {
                    if !primary {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.rule), lineWidth: 1)
                    }
                }
        }
        .widgetAccentable(primary)
    }
}
