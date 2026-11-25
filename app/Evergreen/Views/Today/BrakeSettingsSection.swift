import SwiftUI

/// In Your data: what the brake reads and sends, and how to change it
/// (plan items 1 and 4, business notes BN2).
struct BrakeSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Editing?

    enum Editing: String, Identifiable {
        case calendars, injury
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var profile = model.profile
        VStack(alignment: .leading, spacing: Theme.lg) {
            group("Training calendars") {
                Text(calendarLine)
                Button("Change") { editing = .calendars }
                    .buttonStyle(GhostButtonStyle())
            }
            group("Injury in the last 12 months") {
                Text(injuryLine)
                Button("Change") { editing = .injury }
                    .buttonStyle(GhostButtonStyle())
            }
            group("What leaves your phone") {
                Toggle(isOn: uploads) {
                    Text("Send my answers to Evergreen, without my name")
                }
                .tint(Theme.accent)
                .padding(.trailing, Theme.xs)
                Toggle(isOn: research) {
                    Text("Let researchers use them to study running injuries")
                }
                .tint(Theme.accent)
                .padding(.trailing, Theme.xs)
                .disabled(profile.uploadsAllowed != true)
                Text("Never sent: your Apple Health data itself, where an injury or pain is, or calendar event titles.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .sheet(item: $editing) { editing in
            NavigationStack {
                Group {
                    switch editing {
                    case .calendars: TrainingCalendarsStep(onDone: { self.editing = nil })
                    case .injury: InjuryStep(onDone: { self.editing = nil })
                    }
                }
                .padding(.horizontal, Theme.md)
                .padding(.bottom, Theme.lg)
                .background(Theme.surface)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { self.editing = nil }
                    }
                }
            }
        }
    }

    private var uploads: Binding<Bool> {
        Binding(get: { model.profile.uploadsAllowed == true },
                set: { model.setConsent(uploads: $0, research: $0 && model.profile.researchAllowed) })
    }

    private var research: Binding<Bool> {
        Binding(get: { model.profile.researchAllowed },
                set: { model.setConsent(uploads: model.profile.uploadsAllowed == true, research: $0) })
    }

    private var calendarLine: String {
        let picked = model.profile.trainingCalendarIds
        guard !picked.isEmpty else { return "None picked. Evergreen checks your runs only on calendars you pick." }
        let names = model.trainingCalendarOptions().filter { picked.contains($0.id) }.map(\.title)
        return names.isEmpty ? "\(picked.count) picked" : names.joined(separator: ", ")
    }

    private var injuryLine: String {
        guard model.profile.injuryAnswered else { return "Not answered yet." }
        guard let month = model.profile.injuryMonth else { return "No." }
        return "Yes, \(month.formatted(.dateTime.month(.wide).year())). The rule is tighter for 12 months after."
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
                .accessibilityAddTraits(.isHeader)
            content()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
