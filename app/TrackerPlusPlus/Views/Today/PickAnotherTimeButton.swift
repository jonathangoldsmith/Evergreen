import SwiftUI

/// "Pick another time" on the agent card, with its choices attached to the
/// button so the dialog presents from it. The card's VoiceOver action opens it
/// through the same binding.
struct PickAnotherTimeButton: View {
    let item: PlanItem
    @Binding var isPresented: Bool

    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Pick another time", action: open)
            .buttonStyle(GhostButtonStyle())
            .confirmationDialog("Pick another time", isPresented: $isPresented, titleVisibility: .visible) {
                ForEach(alternatives, id: \.self) { start in
                    Button(label(for: start)) { model.move(item, to: start) }
                }
            }
    }

    private func open() {
        isPresented = true
    }

    /// An hour earlier, an hour or two later, or tomorrow at the same time.
    private var alternatives: [Date] {
        let calendar = Calendar.current
        let start = item.slot.start
        let earliest = model.now.addingTimeInterval(15 * 60)
        let latest = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: start) ?? start
        let sameDay = [-60, 60, 120]
            .compactMap { calendar.date(byAdding: .minute, value: $0, to: start) }
            .filter { $0 >= earliest && $0 <= latest }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start).map { [$0] } ?? []
        return sameDay + tomorrow
    }

    private func label(for date: Date) -> String {
        let when = ActionCopy.when(date, now: model.now)
        return when == "tonight" || when == "today" ? date.clock : "\(when.capitalized) \(date.clock)"
    }
}
