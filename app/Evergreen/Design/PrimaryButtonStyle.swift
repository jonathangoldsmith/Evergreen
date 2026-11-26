import SwiftUI

/// Primary button: solid accent.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.onAccent)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.accent, in: .rect(cornerRadius: Theme.radiusButton))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
