import SwiftUI

/// Small floating button for the demo controls (design D13). Off by default;
/// turned on from the app's page in iOS Settings.
struct DemoButton: View {
    let action: () -> Void

    var body: some View {
        Button("Demo controls", systemImage: "slider.horizontal.3", action: action)
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.text)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(width: 44, height: 44)
            .background(Theme.card, in: .circle)
            .overlay {
                Circle().strokeBorder(Theme.rule, lineWidth: 1)
            }
    }
}
