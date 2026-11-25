import SwiftUI

/// "Buddy" in Your data's People (design decisions 4, 8 and 9): invite a
/// friend with a display name, enter a friend's code, see who you're paired
/// with and their last note, or unpair.
struct BuddySection: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var code = ""
    @State private var invite: BuddyClient.Invite?
    @State private var message: String?
    @State private var busy = false
    @State private var confirmUnpair = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("Buddy")
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
                .accessibilityAddTraits(.isHeader)
            switch model.buddyStatus?.status {
            case "paired": paired
            case "invited": invited
            default: unpaired
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(Theme.textMuted)
            }
        }
        .disabled(busy)
        .task { await model.refreshBuddy() }
        .confirmationDialog("Stop sharing with your buddy?", isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button("Unpair", role: .destructive) { run { await model.unpairBuddy() } }
        } message: {
            Text("Your buddy's row disappears for both of you. They aren't told.")
        }
    }

    // MARK: States

    @ViewBuilder
    private var unpaired: some View {
        Text("A friend gets a short note when you finish a workout, like \"Alex did a 15-minute walk.\" Never a miss.")
        TextField("The name your buddy sees", text: $name)
            .textContentType(.givenName)
            .padding(.horizontal, Theme.sm)
            .frame(minHeight: 44)
            .overlay { RoundedRectangle(cornerRadius: Theme.radiusButton).strokeBorder(Theme.rule) }
        Button("Get an invite code") {
            run {
                switch await model.inviteBuddy(name: name) {
                case .success(let made): invite = made
                case .failure(let failure): message = say(failure)
                }
            }
        }
        .buttonStyle(GhostButtonStyle())
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        Text("Have a friend's code?").font(.footnote).foregroundStyle(Theme.textMuted).padding(.top, Theme.sm)
        TextField("8-character code", text: $code)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .font(.body.monospaced())
            .padding(.horizontal, Theme.sm)
            .frame(minHeight: 44)
            .overlay { RoundedRectangle(cornerRadius: Theme.radiusButton).strokeBorder(Theme.rule) }
        Button("Pair with my friend") {
            run { message = await model.redeemBuddy(code: code).map(say) }
        }
        .buttonStyle(GhostButtonStyle())
        .disabled(code.trimmingCharacters(in: .whitespaces).count != 8)
    }

    @ViewBuilder
    private var invited: some View {
        if let invite {
            Text(invite.code)
                .font(.title2.monospaced().weight(.semibold))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
            ShareLink(item: "Join me on Evergreen as my buddy. My code: \(invite.code)") {
                Label("Send the code", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(GhostButtonStyle())
        } else {
            Text("Your invite is waiting for your friend.")
        }
        Text("It works once and expires in 48 hours. Your friend enters it in Evergreen.")
            .font(.footnote).foregroundStyle(Theme.textMuted)
    }

    @ViewBuilder
    private var paired: some View {
        if model.buddyStatus?.role == "friend" {
            Text("Your buddy: \(model.buddyStatus?.buddyName ?? "your friend")")
            if let note = model.buddyStatus?.notes?.first {
                Text(note.text).font(.footnote).foregroundStyle(Theme.textMuted)
            }
        } else {
            Text("Paired. Your friend gets a note when you finish a workout, never a miss.")
        }
        Button("Unpair") { confirmUnpair = true }
            .buttonStyle(GhostButtonStyle())
    }

    // MARK: Helpers

    private func say(_ failure: BuddyClient.Failure) -> String {
        switch failure {
        case .unreachable: BuddyCopy.unreachable
        case .refused(let reason): BuddyCopy.refusal(reason)
        }
    }

    private func run(_ work: @escaping () async -> Void) {
        busy = true
        message = nil
        Task {
            await work()
            busy = false
        }
    }
}
