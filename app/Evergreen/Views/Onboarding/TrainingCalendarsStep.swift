import SwiftUI

/// "Which calendars hold your training plan?" (plan item 1). Runs are read
/// from these only, and never changed.
struct TrainingCalendarsStep: View {
    let onDone: () -> Void

    @Environment(AppModel.self) private var model
    @State private var options: [TrainingCalendarOption] = []
    @State private var picked: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.md) {
                    Text("Which calendars hold your training plan?")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Text("Runna, TrainingPeaks or your coach's calendar. I check each run on them against your recent running. I never change them.")
                        .font(.body)
                        .foregroundStyle(Theme.text)
                    if model.calendarAccess != .on {
                        Text("Calendar access is off, so there's nothing to pick yet. You can turn it on in Settings, then pick them in Your data.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textMuted)
                    } else if options.isEmpty {
                        Text("No calendars found.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textMuted)
                    }
                    VStack(spacing: 0) {
                        ForEach(options) { option in
                            Toggle(isOn: binding(option.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title).font(.body).foregroundStyle(Theme.text)
                                    if !option.source.isEmpty {
                                        Text(option.source).font(.footnote).foregroundStyle(Theme.textMuted)
                                    }
                                }
                            }
                            .tint(Theme.accent)
                    // Room for the switch's rounded end inside the scroll view's clip.
                    .padding(.trailing, Theme.xs)
                            .frame(minHeight: 44)
                            .padding(.vertical, Theme.xs)
                            Rectangle().fill(Theme.rule).frame(height: 1)
                        }
                    }
                }
                .padding(.top, Theme.lg)
            }
            Button(picked.isEmpty ? "I don't have one" : "Continue") {
                model.setTrainingCalendars(picked)
                onDone()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, Theme.md)
        }
        .onAppear(perform: load)
    }

    private func load() {
        options = model.trainingCalendarOptions()
        picked = model.profile.trainingCalendarsPicked
            ? model.profile.trainingCalendarIds
            : Set(options.filter(\.suggested).map(\.id))
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { picked.contains(id) }, set: { on in
            if on { picked.insert(id) } else { picked.remove(id) }
        })
    }
}
