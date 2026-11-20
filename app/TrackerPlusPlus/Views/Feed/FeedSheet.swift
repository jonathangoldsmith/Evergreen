import SwiftUI

/// Every agent action, newest first, each with Undo (design D9).
struct FeedSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.feed) { action in
                        FeedRow(action: action)
                        Rectangle().fill(Theme.rule).frame(height: 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.md)
            }
            .overlay {
                if model.feed.isEmpty {
                    ContentUnavailableView(
                        "Nothing yet",
                        systemImage: "list.bullet",
                        description: Text("When I move, book or shrink a workout, it shows up here.")
                    )
                }
            }
            .background(Theme.surface)
            .navigationTitle("What I did")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
