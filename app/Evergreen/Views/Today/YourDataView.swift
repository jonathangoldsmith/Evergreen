import SwiftUI

/// What Evergreen read from Apple Health, what its planner keeps (under an
/// anonymous id, never a name), and a way to erase the planner's copy.
struct YourDataView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kept = Kept.loading
    @State private var confirmErase = false

    enum Kept: Equatable {
        case loading
        case loaded(UserDataClient.Kept)
        case unreachable
        case erased
        case notConfigured
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.lg) {
                    section("On this phone") {
                        Text("\(model.health.workouts.count) workouts from the last \(HealthReader.workoutDays) days and \(model.health.days.count) days of sleep and resting heart rate, read from Apple Health.")
                        if let readAt = model.health.readAt {
                            Text("Last read \(readAt.formatted(date: .abbreviated, time: .shortened)).")
                                .font(.footnote)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    BrakeSettingsSection()
                    VStack(alignment: .leading, spacing: Theme.md) {
                        Text("People")
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                            .accessibilityAddTraits(.isHeader)
                        BuddySection()
                    }
                    section("On Evergreen's planner") {
                        Text("To plan your week, your workouts, sleep and resting heart rate are sent to Evergreen's planner and kept under an anonymous ID. No name, email or account is attached.")
                        planner
                    }
                    Text("Anonymous ID: \(DeviceIdentity.userId)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(Theme.textMuted)
                        .textSelection(.enabled)
                }
                .font(.body)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.md)
                .padding(.vertical, Theme.lg)
            }
            .background(Theme.surface)
            .navigationTitle("Your data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete your data from Evergreen's planner?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await erase() } }
            } message: {
                Text("This erases the history, recommendations, answers and age check kept under your anonymous ID. Apple Health and this phone keep theirs. The next plan sends your history again.")
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private var planner: some View {
        switch kept {
        case .loading:
            ProgressView()
        case .notConfigured:
            Text("The planner isn't set up on this build, so nothing has been sent.")
                .foregroundStyle(Theme.textMuted)
        case .unreachable:
            Text("Couldn't reach the planner to check.")
                .foregroundStyle(Theme.textMuted)
            Button("Try again") { Task { await load() } }
                .buttonStyle(GhostButtonStyle())
        case .erased:
            Label("Deleted from the planner", systemImage: "checkmark")
                .foregroundStyle(Theme.accent)
        case .loaded(let info):
            Text(keptLine(info))
                .foregroundStyle(Theme.textMuted)
            if info.historyStored || info.recommendations > 0 || (info.guardrailEvents ?? 0) > 0 {
                Button("Delete my data from the planner", role: .destructive) { confirmErase = true }
                    .buttonStyle(GhostButtonStyle())
                    .padding(.top, Theme.xs)
            }
        }
    }

    private func keptLine(_ info: UserDataClient.Kept) -> String {
        let events = info.guardrailEvents ?? 0
        guard info.historyStored || events > 0 else { return "Nothing kept right now." }
        var parts: [String] = []
        if info.historyStored { parts.append("\(info.workouts) workouts and \(info.days) days") }
        if info.recommendations > 0 { parts.append("\(info.recommendations) past recommendations") }
        if events > 0 { parts.append("\(events) answers and choices") }
        return "Kept: " + parts.joined(separator: "; ") + "."
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
                .accessibilityAddTraits(.isHeader)
            content()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func load() async {
        guard let client = UserDataClient.configured() else { kept = .notConfigured; return }
        kept = .loading
        do { kept = .loaded(try await client.kept()) } catch { kept = .unreachable }
    }

    private func erase() async {
        guard let client = UserDataClient.configured() else { return }
        do {
            try await client.erase()
            kept = .erased
        } catch {
            kept = .unreachable
        }
    }
}
