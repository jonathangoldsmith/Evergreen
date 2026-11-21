import SwiftUI

/// The harness planner's next 7 days, read-only: why the week is sized the way
/// it is, each day's session with its reason and source, and optional extras
/// that are never booked. A sheet, like Why.
struct WeekPlanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.loading

    enum Phase {
        case loading
        case loaded(WeekPlan)
        case failed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your next 7 days")
                        .agentFont(28, relativeTo: .title)
                        .foregroundStyle(Theme.accent)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, Theme.sm)
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.md)
                .padding(.vertical, Theme.lg)
            }
            .background(Theme.surface)
            .navigationTitle("Planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            HStack(spacing: Theme.sm) {
                ProgressView()
                Text("Planning from your health data, shoes and calendar…")
                    .font(.body)
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.vertical, Theme.lg)
        case .failed:
            VStack(alignment: .leading, spacing: Theme.md) {
                Text("Couldn't reach the planner. Your plan on Today is unchanged.")
                    .font(.body)
                    .foregroundStyle(Theme.textMuted)
                Button("Try again") { Task { await load() } }
                    .buttonStyle(GhostButtonStyle())
            }
            .padding(.vertical, Theme.md)
        case .loaded(let plan):
            loaded(plan)
        }
    }

    @ViewBuilder
    private func loaded(_ plan: WeekPlan) -> some View {
        if let summary = plan.summary {
            Text(summary)
                .font(.body)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Theme.md)
        }
        Rectangle().fill(Theme.rule).frame(height: 1)
        ForEach(plan.sessions) { session in
            sessionRow(session)
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
        if let suggestions = plan.suggestions, !suggestions.isEmpty {
            Text("Suggested, not booked")
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Theme.lg)
            ForEach(suggestions) { suggestion in
                suggestionRow(suggestion)
                Rectangle().fill(Theme.rule).frame(height: 1)
            }
        }
        Text(footer(plan))
            .font(.footnote)
            .foregroundStyle(Theme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Theme.lg)
    }

    private func sessionRow(_ session: WeekPlan.Session) -> some View {
        HStack(alignment: .top, spacing: Theme.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dayLine(session))
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.text)
                if let slot = session.after {
                    Text("\(Activity.title(slot.activityType)) · \(slot.minutes) min")
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                } else {
                    Text(session.title)
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                }
                Text(session.reason)
                    .font(.footnote)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                if let citation = session.evidence?.first {
                    sourceLine(citation.source, link: citation.link)
                }
            }
            Spacer(minLength: Theme.sm)
            if let slot = session.after {
                Text(slot.start.clock)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(Theme.text)
            }
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private func suggestionRow(_ suggestion: WeekPlan.Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text([suggestion.title, suggestion.minutes.map { "\($0) min" }].compactMap(\.self).joined(separator: " · "))
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.text)
            if let when = suggestion.when {
                Text(when.prefix(1).uppercased() + when.dropFirst())
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
            }
            if let why = suggestion.why {
                Text(why)
                    .font(.footnote)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            if let source = suggestion.source, let name = source.host ?? source.title {
                sourceLine(name, link: source.link)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "Source: Half Marathon Taper … (runnersblueprint.com)", a link when the planner sent one.
    @ViewBuilder
    private func sourceLine(_ name: String, link: URL?) -> some View {
        let label = Label(name, systemImage: "link")
            .font(.footnote)
            .foregroundStyle(Theme.textMuted)
            .lineLimit(2)
            .padding(.top, 2)
        if let link {
            Link(destination: link) { label }
                .accessibilityHint("Opens the source in Safari")
        } else {
            label
        }
    }

    /// "Saturday, Nov 21", or the session's own title for a note.
    private func dayLine(_ session: WeekPlan.Session) -> String {
        guard let start = session.after?.start else { return session.title }
        return start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func footer(_ plan: WeekPlan) -> String {
        let reasons = plan.source == "sie" ? "Reasons written by Superlinked SIE." : "Reasons from the planner's rules."
        let memory = plan.memorySource == "phone"
            ? "Planned from this phone's memory."
            : "Planned from the memory agent's copy of your history."
        return "\(memory) \(reasons) A preview: nothing here is added to your calendar."
    }

    private func load() async {
        guard let client = PlannerClient.configured() else {
            phase = .failed
            return
        }
        phase = .loading
        do {
            phase = .loaded(try await client.week(model.plannerRequest()))
        } catch {
            phase = .failed
        }
    }
}
