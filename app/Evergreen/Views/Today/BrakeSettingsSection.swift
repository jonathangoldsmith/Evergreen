import SwiftUI

/// In Your data's Form: what the brake reads and sends, and how to change it
/// (plan items 1 and 4, business notes BN2).
struct BrakeSettingsSection: View {
    @Environment(AppModel.self) private var model
    /// Owned by Your data, which presents the one editor sheet: a modifier on a
    /// Section is copied to each of its rows.
    @Binding var editing: Editing?

    enum Editing: String, Identifiable {
        case calendars, injury
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var profile = model.profile
        Section {
            valueRow("Training calendars", value: calendarValue) { editing = .calendars }
            valueRow("Injury in the last 12 months", value: injuryValue) { editing = .injury }
        } header: {
            Text("The brake")
        } footer: {
            Text(brakeFooter)
        }
        .listRowBackground(Theme.card)
        Section {
            Toggle("Send my answers to Evergreen, without my name", isOn: uploads)
            Toggle("Let researchers use them to study running injuries", isOn: research)
                .disabled(profile.uploadsAllowed != true)
        } header: {
            Text("What leaves your phone")
        } footer: {
            Text("Never sent: your Apple Health data itself, where an injury or pain is, or calendar event titles.")
        }
        .listRowBackground(Theme.card)
    }

    /// A Settings-style row: the name, its current value, and a chevron; tapping edits it.
    private func valueRow(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.sm) {
                Text(title).foregroundStyle(Theme.text)
                Spacer(minLength: Theme.sm)
                Text(value).foregroundStyle(Theme.textMuted).multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHint("Changes it")
    }

    private var uploads: Binding<Bool> {
        Binding(get: { model.profile.uploadsAllowed == true },
                set: { model.setConsent(uploads: $0, research: $0 && model.profile.researchAllowed) })
    }

    private var research: Binding<Bool> {
        Binding(get: { model.profile.researchAllowed },
                set: { model.setConsent(uploads: model.profile.uploadsAllowed == true, research: $0) })
    }

    private var calendarValue: String {
        let picked = model.profile.trainingCalendarIds
        guard !picked.isEmpty else { return "None" }
        let names = model.trainingCalendarOptions().filter { picked.contains($0.id) }.map(\.title)
        return names.isEmpty ? "\(picked.count) picked" : names.joined(separator: ", ")
    }

    private var injuryValue: String {
        guard model.profile.injuryAnswered else { return "Not answered" }
        guard let month = model.profile.injuryMonth else { return "No" }
        return month.formatted(.dateTime.month(.wide).year())
    }

    /// What the two rows mean, said once below them.
    private var brakeFooter: String {
        let calendars = "Evergreen checks runs only on the calendars you pick, and never changes them."
        guard model.profile.injuryMonth != nil else { return calendars }
        return calendars + " After an injury, the rule is tighter for 12 months."
    }
}

extension BrakeSettingsSection.Editing {
    /// The editor for one of the brake's rows, in its own navigation stack.
    @MainActor
    func sheet(close: @escaping () -> Void) -> some View {
        NavigationStack {
            Group {
                switch self {
                case .calendars: TrainingCalendarsStep(onDone: close)
                case .injury: InjuryStep(onDone: close)
                }
            }
            .padding(.horizontal, Theme.md)
            .padding(.bottom, Theme.lg)
            .background(Theme.surface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }
            }
        }
    }
}
