import SwiftUI

/// The run decision on Today (design decisions 7, 13 and 14), for one run on
/// a training calendar: the morning check, the swap question, or what was
/// chosen with Undo until the run starts. VoiceOver reads each state as one
/// sentence, with the buttons as named actions (design decision 16).
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
            } else if let check = model.checkIn(for: run) {
                checked(check)
            }
        }
        .padding(model.runUrgency(run) == .note ? Theme.md : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .agentCardBackground(colorScheme)
    }

    // MARK: The swap

    private func question(_ flag: GuardrailFlag) -> some View {
        let hurtMonth = model.hurtAfterJumpMonth(for: flag)
        return VStack(alignment: .leading, spacing: Theme.sm) {
            Text(GuardrailCopy.question(run, flag, now: model.now))
                .agentFont(24, relativeTo: .title2)
                .foregroundStyle(Theme.accent)
            if !flag.keepEasy {
                (Text(flag.planned.label).strikethrough(color: Theme.textMuted).foregroundStyle(Theme.textMuted)
                    + Text(" → \(flag.suggested.label)").foregroundStyle(Theme.text))
                    .font(.body.monospacedDigit())
            }
            Text(GuardrailCopy.reason(flag)).font(.body).foregroundStyle(Theme.text)
            if let hurtMonth {
                Text(Self.hurtLine(hurtMonth))
                    .font(.body)
                    .foregroundStyle(Theme.text)
            }
            Text(GuardrailCopy.sourceNote(run, flag.planned))
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
            ChoiceRow { choices(flag) }
                .padding(.top, Theme.sm)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GuardrailCopy.spoken(run, flag, now: model.now) + (hurtMonth.map { " " + Self.hurtLine($0) } ?? ""))
        .accessibilityActions {
            Button(GuardrailCopy.accept(flag)) { model.acceptSwap(run, flag: flag) }
            Button(GuardrailCopy.keep(flag)) { model.keepPlan(run, flag: flag) }
        }
        .onAppear { model.noteFlagShown(run, flag) }
    }

    private static func hurtLine(_ month: String) -> String {
        "You were hurt after a jump like this in \(month)."
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
            Text(GuardrailCopy.runLine(run))
                .font(.body)
                .foregroundStyle(Theme.text)
            if decision.choice == .accept {
                Text(GuardrailCopy.sourceNote(run, decision.planned))
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
                if model.calendarAccess != .on {
                    // Design decision 7: the swap lives in Evergreen until it can reach the calendar.
                    Text(GuardrailCopy.calendarOff)
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            Button("Undo") { model.undoDecision(decision) }
                .buttonStyle(GhostButtonStyle())
                .padding(.top, Theme.sm)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GuardrailCopy.spokenDecided(decision, run: run, calendarOn: model.calendarAccess == .on))
        .accessibilityActions {
            Button("Undo") { model.undoDecision(decision) }
        }
    }

    // MARK: Morning check

    private var morningCheck: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("How do your legs feel?")
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text(GuardrailCopy.runLine(run))
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
            ChoiceRow { answers }
                .padding(.top, Theme.sm)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GuardrailCopy.spokenMorningCheck(run))
        .accessibilityActions {
            ForEach(MorningCheck.allCases, id: \.self) { answer in
                Button(answer.label) { model.answerMorningCheck(run, answer) }
            }
        }
    }

    /// After the answer, with no swap to offer, the card shrinks to one line
    /// until the run starts (design decision 7).
    private func checked(_ check: MorningCheck) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Text(GuardrailCopy.checkedIn(check))
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text(GuardrailCopy.runLine(run))
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GuardrailCopy.spokenCheckedIn(check, run: run))
    }

    private var answers: some View {
        ForEach(MorningCheck.allCases, id: \.self) { answer in
            Button(answer.label) { model.answerMorningCheck(run, answer) }
                .buttonStyle(GhostButtonStyle())
        }
    }
}
