import SwiftUI

/// One planned workout. Missed ones are muted, never red (design D7).
struct PlanRow: View {
    let item: PlanItem

    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Theme.md) {
            Text(item.slot.start.clock)
                .font(.body.monospacedDigit())
                .foregroundStyle(Theme.textMuted)
                .frame(minWidth: 76, alignment: .leading)
            Image(systemName: Activity.symbol(item.slot.activityType))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(Activity.title(item.slot.activityType))
                    .font(.body)
                    .foregroundStyle(Theme.text)
                    .strikethrough(isMissed, color: Theme.textMuted)
                Text("\(item.slot.minutes) min\(item.source == .comeback ? " · 2× points" : "")")
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: Theme.sm)
            status
        }
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var isMissed: Bool { model.isMissed(item) }

    @ViewBuilder
    private var status: some View {
        if model.completion(for: item) != nil {
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.success)
        } else if isMissed {
            Text("Didn't happen")
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
        }
    }
}
