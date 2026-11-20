import SwiftUI

/// Home (design D4): the agent's latest action, today's workouts, and a link to
/// the week. "Missed one" is the card's state here, not its own screen.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var showFeed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.lg) {
                    if model.offline {
                        Label("Offline, showing last update", systemImage: "wifi.slash")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                    if let action = model.latestAction {
                        AgentCard(action: action)
                    } else {
                        QuietState()
                    }
                    TodayPlanSection()
                    WeekLink()
                    Text("Using \(model.persona.name)'s demo data")
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.horizontal, Theme.md)
                .padding(.vertical, Theme.lg)
            }
            .background(Theme.surface)
            .navigationTitle("Today")
            .navigationDestination(for: TodayRoute.self) { route in
                switch route {
                case .week: WeekView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("What I did", systemImage: "list.bullet", action: openFeed)
                }
            }
            .sheet(isPresented: $showFeed) { FeedSheet() }
        }
    }

    private func openFeed() {
        showFeed = true
    }
}
