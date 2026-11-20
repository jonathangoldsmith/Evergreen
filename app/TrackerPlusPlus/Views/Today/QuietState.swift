import SwiftUI

/// Today with nothing for the agent to report (design review state table).
struct QuietState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("I'll act when your plan needs it.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
            Text("Your workouts are planned. If something gets in the way, I'll move or rebook it and tell you here.")
                .font(.body)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.vertical, Theme.sm)
    }
}
