import SwiftUI

/// The run decision on Today (design decisions 7, 13 and 14), for one run on
/// a training calendar: the morning check, the swap question, or what was
/// chosen with Undo until the run starts.
struct GuardrailCard: View {
    let run: PlannedRun

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let decision = model.decision(for: run) {
                decided(decision)
            } else if let flag = model.flag(for: run) {
                question(flag)
            } else if model.needsMorningCheck(run) {
                morningCheck
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .agentCardBackground(colorScheme)
    }

    // MARK: The swap

    private func question(_ flag: GuardrailFlag) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text(GuardrailCopy.question(run, flag, now: model.now))
                .agentFont(24, relativeTo: .title2)
                .foregroundStyle(Theme.accent)
            if !flag.keepEasy {
                (Text(flag.planned.label).strikethrough(color: Theme.textMuted).foregroundStyle(Theme.textMuted)
                    + Text(" → \(flag.suggested.label)").foregroundStyle(Theme.text))
                    .font(.body.monospacedDigit())
            }
            Text(GuardrailCopy.reason(flag)).font(.body).foregroundStyle(Theme.text)
            if let month = model.hurtAfterJumpMonth(for: flag) {
                Text("You were hurt after a jump like this in \(month).")
                    .font(.body)
                    .foregroundStyle(Theme.text)
            }
            Text(GuardrailCopy.sourceNote(run, flag.planned))
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.sm) { choices(flag) }
                VStack(spacing: Theme.sm) { choices(flag) }
            }
            .padding(.top, Theme.sm)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(GuardrailCopy.spoken(run, flag, now: model.now))
        .onAppear { model.noteFlagShown(run, flag) }
    }

    @ViewBuilder
    private func choices(_ flag: GuardrailFlag) -> some View {
        Button(GuardrailCopy.accept(flag)) { model.acceptSwap(run, flag: flag) }
            .buttonStyle(PrimaryButtonStyle())
        Button(GuardrailCopy.keep(flag)) { model.keepPlan(run, flag: flag) }
            .buttonStyle(GhostButtonStyle())
    }

    // MARK: After the choice

    private func decided(_ decision: GuardrailDecision) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text(GuardrailCopy.decided(decision))
                .agentFont(24, relativeTo: .title2)
                .foregroundStyle(Theme.accent)
            Text("\(run.start.formatted(.dateTime.weekday(.wide))) · \(run.title) at \(run.start.clock)")
                .font(.body)
                .foregroundStyle(Theme.text)
            if decision.choice == .accept {
                Text(GuardrailCopy.sourceNote(run, decision.planned))
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
            }
            Button("Undo") { model.undoDecision(decision) }
                .buttonStyle(GhostButtonStyle())
                .padding(.top, Theme.sm)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Morning check

    private var morningCheck: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("How do your legs feel?")
                .font(.headline)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Text("\(run.start.formatted(.dateTime.weekday(.wide))) · \(run.title) at \(run.start.clock)")
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.sm) { answers }
                VStack(spacing: Theme.sm) { answers }
            }
            .padding(.top, Theme.sm)
        }
    }

    private var answers: some View {
        ForEach(MorningCheck.allCases, id: \.self) { answer in
            Button(answer.label) { model.answerMorningCheck(run, answer) }
                .buttonStyle(GhostButtonStyle())
        }
    }
}
