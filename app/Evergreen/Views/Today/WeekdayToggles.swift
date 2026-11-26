import SwiftUI

/// Seven 44 pt weekday toggles, Monday first, labeled in full for VoiceOver
/// (design decision 19). 1 = Sunday … 7 = Saturday, like Calendar's weekday.
struct WeekdayToggles: View {
    @Binding var selected: Set<Int>

    private static let order = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        HStack(spacing: Theme.xs) {
            ForEach(Self.order, id: \.self) { weekday in
                let on = selected.contains(weekday)
                Button {
                    if on { selected.remove(weekday) } else { selected.insert(weekday) }
                } label: {
                    Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        // A picked day is outlined and tinted, not filled, so
                        // Start stays the card's one solid accent button.
                        .foregroundStyle(on ? Theme.accent : Theme.text)
                        .background(on ? Theme.accent.opacity(0.12) : Color.clear, in: .rect(cornerRadius: Theme.radiusSmall))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                .strokeBorder(on ? Theme.accent : Theme.rule, lineWidth: on ? 2 : 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        // Seven letters must fit one row; VoiceOver reads the full day names.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}
