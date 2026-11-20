import SwiftUI

/// "in 4:59:12" counting down to the start, "Now" once it's time, or the
/// points earned when it's done.
struct WorkoutTimeText: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .done:
            Text("\(state.points) pts")
        case .upcoming:
            if state.countdownTo > .now {
                Text(timerInterval: Date.now...state.countdownTo, countsDown: true, showsHours: true)
            } else {
                Text("Now")
            }
        }
    }
}
