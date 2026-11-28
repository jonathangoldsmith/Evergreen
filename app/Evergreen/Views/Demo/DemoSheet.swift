import SwiftUI

/// The demo controls: one button per beat. Each beat starts from a clean run
/// for Jordan, so they can be shown in any order.
struct DemoSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var sampleStatus: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    beat("The plan", detail: "Three workouts tailored from Apple Health and your calendar.") {
                        model.showPlan()
                    }
                    beat("A meeting moves a workout", detail: "Friday, 4 PM: a \"Team sync\" lands on tonight's 6 PM run. Evergreen moves it and sends a notification.") {
                        model.showMovedDemo()
                    }
                    .disabled(model.calendarAccess != .on)
                    beat("A missed walk books a comeback", detail: "Sam, 1:30 PM: today's noon walk was missed, so Evergreen books a 15-minute walk tonight for double points.") {
                        model.showComebackDemo()
                    }
                    beat("Finish the comeback", detail: "Logs Sam's comeback walk at its time: the Done sheet shows 2× points and the buddy celebrates.") {
                        model.finishComebackDemo()
                    }
                    .disabled(!model.plan.contains { $0.source == .comeback })
                    beat("Coming back from an injury", detail: "An injury last month: Today offers a 4-week walk-run plan on your usual days, and pauses Runna's runs while it lasts.") {
                        model.showReturnDemo()
                    }
                    beat("A big jump on tomorrow's long run", detail: "A Runna-style calendar plans 2½ hours; Jordan's longest this month was under 2. Evergreen asks to shorten it and leaves Runna's event alone.") {
                        model.showBrakeDemo()
                    }
                    .disabled(model.calendarAccess != .on)
                    beat("The morning of a run", detail: "8 AM before an easy 40-minute evening run: Today asks how your legs feel, then shrinks to one line after the answer.") {
                        model.showMorningCheckDemo()
                    }
                    .disabled(model.calendarAccess != .on)
                    beat("A rough night before a long run", detail: "7 AM: Jordan slept 5h 40 and his resting heart rate is 6 over his usual. Before he answers how his legs feel, Today offers a shorter evening long run.") {
                        model.showRoughNightDemo()
                    }
                    .disabled(model.calendarAccess != .on)
                    beat("The night before a long run", detail: "8:30 PM before a 7 AM long run: Jordan usually sleeps about 7h 30, so Evergreen says lights out by 10:30, on Today and on the Lock Screen.") {
                        model.showBedtimeDemo()
                    }
                    .disabled(model.calendarAccess != .on)
                    beat("Sunday evening", detail: "This Sunday at 6:30 PM: tomorrow's long run is a big jump and the week's pain question is open, so both cards stack in order. Shows nothing new if this week is already answered.") {
                        model.showSundayDemo()
                    }
                    .disabled(model.calendarAccess != .on)
                    beat("Rain: suggest a gym day pass", detail: "Rain on Saturday's 8:30 AM long run; Evergreen suggests a $15 pass at 24 Hour Fitness in San Francisco and books it only if you say yes.") {
                        model.showRainDemo()
                    }
                    .disabled(model.rainTime == nil)
                    beat("You, from Apple Health", detail: "Your own week, planned from your workouts, sleep, resting heart rate and heart rate variability in Apple Health.") {
                        Task { await model.useAppleHealth() }
                    }
                    #if DEBUG
                    Button("Add a month of sample data to Apple Health") {
                        Task {
                            sampleStatus = "Adding…"
                            do {
                                let added = try await HealthSampleData.fill(storyDay: model.storyDay)
                                sampleStatus = "Added \(added) workouts and 28 nights."
                                await model.refreshHealth()
                            } catch {
                                sampleStatus = "Couldn't write to Apple Health."
                            }
                        }
                    }
                    if let sampleStatus {
                        Text(sampleStatus).font(.footnote).foregroundStyle(Theme.textMuted)
                    }
                    #endif
                    beat("Shoes near 400 miles", detail: "392 miles on the pair, race in 9 days; the agent asks before buying.") {
                        model.showShoesDemo()
                    }
                } footer: {
                    Text(footer)
                }

                Section {
                    LabeledContent("Sent since launch", value: model.amplitudeOn ? "\(model.amplitudeSent)" : "Off")
                    LabeledContent("Waiting to send", value: "\(model.memoryReport?.pending ?? 0)")
                    if let problem = model.memoryReport?.problem {
                        LabeledContent("Last problem", value: problem)
                    }
                    Button("Sync memory now") { Task { await model.syncMemory() } }
                } header: {
                    Text("Amplitude")
                } footer: {
                    Text("Each tick rolls the person's memory and hands workout and memory events to the Amplitude SDK; Order it sends Purchase Approved. The key comes from app/Secrets.xcconfig at build time. Ids are opaque; no names or health readings leave the phone.")
                }
            }
            .navigationTitle("Demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// One beat: runs it and closes the sheet so Today shows the result.
    private func beat(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.text)
                Text(detail).font(.footnote).foregroundStyle(Theme.textMuted)
            }
            .padding(.vertical, Theme.xs)
        }
    }

    private var footer: String {
        var lines = ["Demo merchants, no charge."]
        if model.calendarAccess != .on { lines.append("The meeting beat needs calendar access.") }
        if model.rainTime == nil { lines.append("The rain beat needs Saturday's run on the plan.") }
        return lines.joined(separator: " ")
    }
}
