import SwiftUI

/// This week, top to bottom (design D17): progress as a sentence, then one row
/// per day with finished workouts checked and planned ones timed.
struct WeekView: View {
    @Environment(AppModel.self) private var model

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    private var days: [Date] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: model.storyDay) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.lg) {
                if let response = model.response {
                    Text("\(response.weekDone) of \(response.normal.weeklyTarget) this week")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.text)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        Rectangle().fill(Theme.rule).frame(height: 1)
                        DayRow(day: day, isToday: calendar.isDate(day, inSameDayAs: model.storyDay))
                    }
                    Rectangle().fill(Theme.rule).frame(height: 1)
                }
                if let normal = model.normal {
                    Text("Goal: \(normal.goal4Weeks) in 4 weeks, about \(normal.weeklyTarget) a week.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .padding(.horizontal, Theme.md)
            .padding(.vertical, Theme.lg)
        }
        .background(Theme.surface)
        .navigationTitle("This week")
        .navigationBarTitleDisplayMode(.inline)
    }
}
