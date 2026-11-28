import SwiftUI

/// Today's range (TODOS item 3) as one sentence under the date: "Today:
/// 10–45 min, easy effort." and why. Plain text, not a card (DESIGN.md:
/// never make information a card; progress is a sentence, never a ring).
struct TodayRangeLine: View {
    let range: TodayRange

    var body: some View {
        TodaySentence(line: range.line, reason: range.reason)
    }
}

/// One plain sentence on Today and the line under it that says why: today's
/// range, or tonight's bedtime (TODOS item 4).
struct TodaySentence: View {
    let line: String
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.text)
            Text(reason)
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Theme.xs)
        .accessibilityElement(children: .combine)
    }
}
