import SwiftUI

/// "Checking your last year…" (plan item 4, design decisions 5 and 6): up to
/// 8 days asked blind, plain dates and no percentages, then the reveal of
/// where the rule would have stepped in.
struct BacktestStep: View {
    let onDone: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var stage = Stage.loading
    @State private var days: [Backtest.Day] = []
    @State private var questions: [Backtest.Day] = []
    @State private var index = 0

    enum Stage { case loading, thin, asking, reveal }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.md) {
                    switch stage {
                    case .loading: loading
                    case .thin: thin
                    case .asking: asking
                    case .reveal: reveal
                    }
                }
                .padding(.top, Theme.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer.padding(.top, Theme.md)
        }
        .task { await load() }
    }

    private func load() async {
        guard stage == .loading else { return }
        guard let checked = await model.loadBacktest() else { stage = .thin; return }
        days = checked
        questions = Backtest.sample(checked, seed: model.backtestSeed)
        stage = questions.isEmpty ? .reveal : .asking
    }

    // MARK: Stages

    private var loading: some View {
        HStack(spacing: Theme.sm) {
            ProgressView()
            Text("Checking your last year…").font(.body).foregroundStyle(Theme.text)
        }
    }

    private var thin: some View {
        VStack(alignment: .leading, spacing: Theme.md) {
            title("Not enough history to check yet")
            Text("I'll watch from today. If you didn't allow Apple Health, you can turn it on in Settings.")
                .font(.body).foregroundStyle(Theme.text)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(GhostButtonStyle())
        }
    }

    private var asking: some View {
        let day = questions[index]
        return VStack(alignment: .leading, spacing: Theme.md) {
            Text("\(index + 1) of \(questions.count)")
                .font(.footnote).foregroundStyle(Theme.textMuted)
            title("\(day.date.formatted(.dateTime.month(.abbreviated).day())), a \(day.size.rounded.label) run")
            Text("Were you hurt or sore for days within 2 weeks?")
                .font(.body).foregroundStyle(Theme.text)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.sm) { answers(day) }
                VStack(spacing: Theme.sm) { answers(day) }
            }
        }
    }

    private func answers(_ day: Backtest.Day) -> some View {
        ForEach(AppModel.BacktestAnswer.allCases, id: \.self) { answer in
            Button(answer.label) {
                model.answerBacktest(answer, day: day)
                next()
            }
            .buttonStyle(GhostButtonStyle())
        }
    }

    private var reveal: some View {
        let flagged = days.filter(\.flagged)
        return VStack(alignment: .leading, spacing: Theme.md) {
            if flagged.isEmpty {
                title("Your last year stayed in range.")
                Text("None of your runs was a big jump from your longest in the month before.")
                    .font(.body).foregroundStyle(Theme.text)
            } else {
                Text(flagged.count == 1 ? "I'd have stepped in on 1 day" : "I'd have stepped in on \(flagged.count) days")
                    .agentFont(30, relativeTo: .title)
                    .foregroundStyle(Theme.accent)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(flagged.suffix(8)) { day in
                        HStack {
                            Text(day.date.formatted(.dateTime.month(.abbreviated).day().year()))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Text(revealLine(day)).foregroundStyle(Theme.textMuted).monospacedDigit()
                        }
                        .font(.body)
                        .frame(minHeight: 44)
                        Rectangle().fill(Theme.rule).frame(height: 1)
                    }
                }
                if flagged.count > 8 {
                    Text("And \(flagged.count - 8) earlier.").font(.footnote).foregroundStyle(Theme.textMuted)
                }
            }
        }
    }

    /// "24 km, 38% past your longest"
    private func revealLine(_ day: Backtest.Day) -> String {
        guard let percent = day.jumpPercent else { return day.size.rounded.label }
        return "\(day.size.rounded.label), \(percent)% past your longest"
    }

    @ViewBuilder
    private var footer: some View {
        switch stage {
        case .loading:
            EmptyView()
        case .asking:
            Button("Skip the rest") { finish(answered: index) }
                .buttonStyle(GhostButtonStyle())
        case .thin, .reveal:
            Button("Continue", action: onDone)
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.title2.weight(.semibold))
            .foregroundStyle(Theme.text)
            .accessibilityAddTraits(.isHeader)
    }

    private func next() {
        if index + 1 < questions.count {
            index += 1
        } else {
            finish(answered: questions.count)
        }
    }

    private func finish(answered: Int) {
        model.finishBacktest(answered: answered)
        stage = .reveal
    }
}
