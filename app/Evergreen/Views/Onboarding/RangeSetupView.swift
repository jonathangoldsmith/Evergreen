import SwiftUI

/// The range setup after Permissions (plan item 4, design decision 3, BN2):
/// what leaves your phone, which calendars hold your training, the injury
/// question, and the check of the last year. People who onboarded before these steps see them once
/// (eng re-run R8), with "Not now" allowed once.
struct RangeSetupView: View {
    /// True for the one-time catch-up of an existing user.
    var catchUp = false
    let onFinish: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = Step.consent

    /// Steps slide in, or fade under Reduce Motion (design decision 16).
    private var pageTransition: AnyTransition { reduceMotion ? .opacity : .move(edge: .trailing) }

    enum Step: Int, CaseIterable { case consent, calendars, injury, backtest }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if catchUp && model.canDeferRangeSetup {
                HStack {
                    Spacer()
                    Button("Not now") { model.deferRangeSetup() }
                        .font(.body)
                        .foregroundStyle(Theme.textMuted)
                        .frame(minHeight: 44)
                }
            }
            Group {
                switch step {
                case .consent: ConsentStep(onDone: next)
                case .calendars: TrainingCalendarsStep(onDone: next)
                case .injury: InjuryStep(onDone: next)
                case .backtest: BacktestStep(onDone: next)
                }
            }
            .transition(pageTransition)
        }
        .animation(.easeInOut(duration: 0.3), value: step)
        .padding(.horizontal, Theme.md)
        .padding(.bottom, Theme.lg)
        .background(Theme.surface)
    }

    private func next() {
        if let following = Step(rawValue: step.rawValue + 1) {
            step = following
        } else {
            model.finishRangeSetup()
            onFinish()
        }
    }
}
