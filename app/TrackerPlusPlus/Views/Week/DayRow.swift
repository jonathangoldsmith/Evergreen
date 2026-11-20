import SwiftUI

struct DayRow: View {
    let day: Date
    let isToday: Bool

    @Environment(AppModel.self) private var model

    private var finished: [Workout] {
        model.workouts
            .filter { Calendar.current.isDate($0.start, inSameDayAs: day) && $0.minutes >= 10 && $0.start <= model.now }
            .sorted { $0.start < $1.start }
    }

    private var open: [PlanItem] {
        model.plan.filter {
            Calendar.current.isDate($0.slot.start, inSameDayAs: day) && model.completion(for: $0) == nil
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.md) {
            Text(day.formatted(.dateTime.weekday(.abbreviated).day()))
                .font(.body.weight(isToday ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(isToday ? Theme.text : Theme.textMuted)
                .frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                if finished.isEmpty && open.isEmpty {
                    Text("Rest").foregroundStyle(Theme.textMuted)
                }
                ForEach(finished) { workout in
                    Label("\(Activity.title(workout.activityType)) · \(Int(workout.minutes.rounded())) min",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.text)
                        .labelStyle(CheckLabelStyle())
                }
                ForEach(open) { item in
                    Text("\(item.slot.start.clock) · \(Activity.title(item.slot.activityType)), \(item.slot.minutes) min")
                        .foregroundStyle(model.isMissed(item) ? Theme.textMuted : Theme.text)
                        .strikethrough(model.isMissed(item), color: Theme.textMuted)
                }
            }
            .font(.body)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
