import SwiftUI

/// The demo clock (within the story day, eng review D6), "Log a workout" (D5),
/// the person switch, and "Reset demo" (D13).
struct DemoSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// The slider's position in minutes after midnight; set from the clock when the sheet opens.
    @State private var minutes: Double = 13 * 60 + 30
    @State private var confirmReset = false

    /// 6 AM to 11 PM.
    private static let clockRange: ClosedRange<Double> = 360...1380

    private let quickTimes: [(String, Int)] = [("12:00 PM", 12 * 60), ("1:30 PM", 13 * 60 + 30), ("6:45 PM", 18 * 60 + 45)]

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Person") {
                    Picker("Person", selection: $model.personKey) {
                        ForEach(PersonaKey.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    HStack {
                        Text("Now")
                        Spacer()
                        Text(model.clockMinutes == nil ? "Real time, \(model.now.clock)" : model.now.clock)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textMuted)
                    }
                    Slider(value: $minutes, in: Self.clockRange, step: 15) {
                        Text("Time")
                    } onEditingChanged: { editing in
                        if !editing { model.setClock(minutes: Int(minutes)) }
                    }
                    .accessibilityValue(sliderTime)
                    HStack {
                        ForEach(quickTimes, id: \.1) { label, value in
                            Button(label) {
                                minutes = Double(value)
                                model.setClock(minutes: value)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Button("Use real time") { model.setClock(minutes: nil) }
                } header: {
                    Text("Clock")
                } footer: {
                    Text("Moves \"now\" within today, the story day.")
                }

                Section {
                    Button("Log a workout") { model.logWorkout() }
                } footer: {
                    Text("Adds a finished workout ending now, the way the Health import will.")
                }

                Section {
                    Button("Add a meeting on the next workout") { model.addTestMeeting() }
                        .disabled(model.calendarAccess != .on || model.nextDaysFirstWorkout == nil)
                } footer: {
                    if let item = model.nextDaysFirstWorkout {
                        Text("Puts a 1-hour \"Team sync\" on your calendar 15 minutes before the \(item.slot.start.formatted(.dateTime.weekday(.wide).hour().minute())) \(Activity.noun(item.slot.activityType)). Needs calendar access. Reset demo removes it.")
                    }
                }

                Section("Agent") {
                    LabeledContent("Answering /tick", value: model.agentName)
                    Button("Tick now") { Task { await model.tick() } }
                }

                Section {
                    Button("Reset demo", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Clears the agent's actions, logged workouts, points, the clock, the TrackerPlusPlus calendar and the test meeting.")
                }
            }
            .navigationTitle("Demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset the demo?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset demo", role: .destructive) { model.resetDemo() }
            }
            .onAppear(perform: syncSlider)
        }
        .presentationDetents([.medium, .large])
    }

    /// The time the slider points at, for VoiceOver while it moves.
    private var sliderTime: String {
        (Calendar.current.date(byAdding: .minute, value: Int(minutes), to: model.storyDay) ?? model.now).clock
    }

    /// Starts the slider at the demo clock, or at the real time (to the
    /// nearest 15 minutes, inside the slider's range) when there's no demo clock.
    private func syncSlider() {
        if let clock = model.clockMinutes {
            minutes = Double(clock)
            return
        }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: model.now)
        let real = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        minutes = min(max((real / 15).rounded() * 15, Self.clockRange.lowerBound), Self.clockRange.upperBound)
    }
}
