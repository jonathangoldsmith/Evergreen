import SwiftUI

/// Shown on Today when the plan can't go on the calendar (design state table,
/// Permissions row): the plan stays in the app, with a way to turn it on.
struct CalendarOffNotice: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Label("Your plan is only in the app", systemImage: "calendar.badge.exclamationmark")
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text("Turn on Calendar and I'll keep your workouts on a TrackerPlusPlus calendar.")
                .font(.body)
                .foregroundStyle(Theme.textMuted)
            Button("Turn on Calendar", action: turnOn)
                .buttonStyle(GhostButtonStyle())
                .padding(.top, Theme.xs)
        }
    }

    /// Asks the first time; after a denial only Settings can turn it on.
    private func turnOn() {
        if model.calendarAccess == .notAsked {
            Task { await model.requestCalendarAccess() }
        } else if let settings = URL(string: UIApplication.openSettingsURLString) {
            openURL(settings)
        }
    }
}
