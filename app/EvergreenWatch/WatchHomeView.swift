import SwiftUI

/// One screen per step (DESIGN.md's watch rules): today's run, then the
/// morning check or the swap. Agent actions get the accent; nothing is a ring.
struct WatchHomeView: View {
    @Environment(WatchLink.self) private var link

    static let accent = Color(red: 0x5F / 255, green: 0xC2 / 255, blue: 0xA6 / 255)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let run = link.state.run {
                    Text(run.line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    content(run)
                } else {
                    Text(link.state.today)
                        .font(.headline)
                    Text(link.state.inRangeSpoken)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(.black, for: .navigation)
    }

    @ViewBuilder
    private func content(_ run: WatchState.Run) -> some View {
        if link.queued[run.key] != nil {
            Label("Will sync with your phone", systemImage: "iphone.and.arrow.forward")
                .font(.footnote)
        } else if let decided = run.decided {
            Text(decided)
                .font(.headline)
                .foregroundStyle(Self.accent)
        } else if let question = run.question {
            Text(question)
                .font(.headline)
                .foregroundStyle(Self.accent)
            Button(run.acceptLabel ?? "Make it shorter") { link.answer(.accept, for: run.key) }
                .tint(Self.accent)
            Button(run.keepLabel ?? "Keep it") { link.answer(.keep, for: run.key) }
        } else if run.asksCheck {
            Text("How do your legs feel?")
                .font(.headline)
            Button("Fresh") { link.answer(.fresh, for: run.key) }
            Button("Tired") { link.answer(.tired, for: run.key) }
            Button("Sore") { link.answer(.sore, for: run.key) }
        } else {
            Text(link.state.today)
                .font(.headline)
        }
    }
}
