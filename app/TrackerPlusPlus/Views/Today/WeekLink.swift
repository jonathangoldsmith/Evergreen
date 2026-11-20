import SwiftUI

/// "This week: 1 of 3", opening the week view.
struct WeekLink: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationLink(value: TodayRoute.week) {
            HStack {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        guard let response = model.response else { return "This week" }
        return "This week: \(response.weekDone) of \(response.normal.weeklyTarget)"
    }
}
