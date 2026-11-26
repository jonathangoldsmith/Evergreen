import SwiftUI

/// "Any injury in the last 12 months?" (plan item 4), with the
/// not-medical-advice line under it (item 9). The location is never asked here.
struct InjuryStep: View {
    let onDone: () -> Void

    @Environment(AppModel.self) private var model
    @State private var injured: Bool?
    @State private var month = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.md) {
                    Text("Any injury in the last 12 months?")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Text("A recent injury is the biggest sign a run might be too much, so I use a tighter limit for a year after one.")
                        .font(.body)
                        .foregroundStyle(Theme.text)
                    HStack(spacing: Theme.sm) {
                        choice("No", selected: injured == false) { injured = false }
                        choice("Yes", selected: injured == true) { injured = true }
                    }
                    if injured == true {
                        HStack {
                            Text("Roughly when?").font(.body).foregroundStyle(Theme.text)
                            Spacer()
                            Picker("Roughly when?", selection: $month) {
                                ForEach(months, id: \.self) { month in
                                    Text(month.formatted(.dateTime.month(.wide).year())).tag(month)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.text)
                            .labelsHidden()
                        }
                        .frame(minHeight: 44)
                    }
                    Text("Evergreen suggests training changes. It isn't medical advice; see a physio or doctor for pain or injury.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.top, Theme.lg)
            }
            Button("Continue") {
                model.setInjury(month: injured == true ? month : nil)
                onDone()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(injured == nil)
            .opacity(injured == nil ? 0.5 : 1)
            .padding(.top, Theme.md)
        }
        .onAppear {
            month = months.first ?? Date()
            if model.profile.injuryAnswered {
                injured = model.profile.injuryMonth != nil
                if let saved = model.profile.injuryMonth, let match = months.first(where: { $0 == saved }) { month = match }
            }
        }
    }

    /// This month and the 11 before it, newest first.
    private var months: [Date] {
        let cal = Calendar.current
        let thisMonth = cal.dateInterval(of: .month, for: Date())?.start ?? Date()
        return (0..<12).compactMap { cal.date(byAdding: .month, value: -$0, to: thisMonth) }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: selected ? "checkmark.circle.fill" : "circle")
        }
        .buttonStyle(GhostButtonStyle())
        // The picked answer gets a heavier edge, not just a filled icon.
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: Theme.radiusButton).strokeBorder(Theme.text, lineWidth: 2)
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
