import SwiftUI

/// A card's answer buttons (design decision 16): side by side when they fit,
/// and always stacked at accessibility text sizes, where three wrapped
/// buttons in a row are too narrow to read.
struct ChoiceRow<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: Theme.sm) { content }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.sm) { content }
                VStack(spacing: Theme.sm) { content }
            }
        }
    }
}
