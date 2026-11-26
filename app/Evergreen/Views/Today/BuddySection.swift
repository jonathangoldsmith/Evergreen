import SwiftUI

/// "Buddy" in Your data (Your data refreshes it on open) (design decisions 4, 8 and 9): invite a
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
    /// What to do after "Allow and share", while that question is up.
    @State private var afterConsent: (() -> Void)?

    var body: some View {
        Section {
            switch model.buddyStatus?.status {
            case "paired": paired
            case "invited": invited
            default: inviteRows
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(Theme.textMuted)
            }
        } header: {
            Text("Buddy")
        } footer: {
            Text(footer)
        }
        .listRowBackground(Theme.card)
        .disabled(busy)
        .uploadConsentAlert(for: $afterConsent, model: model)
        if isUnpaired {
            Section {
                TextField("8-character code", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button("Pair with my friend") { askingFirst(redeem) }
                .disabled(code.trimmingCharacters(in: .whitespaces).count != 8)
            } header: {
                Text("Have a friend's code?")
            }
            .listRowBackground(Theme.card)
            .disabled(busy)
        }
    }

    private var isUnpaired: Bool {
        let status = model.buddyStatus?.status
        return status != "paired" && status != "invited"
    }

    private var footer: String {
        switch model.buddyStatus?.status {
        case "invited": "It works once and expires in 48 hours. Your friend enters it in Evergreen."
        case "paired": "They get a short note when you finish a workout, never a miss."
        default: "A friend gets a short note when you finish a workout, like \"Alex did a 15-minute walk.\" Never a miss."
        }
    }

    // MARK: States

    @ViewBuilder
    private var inviteRows: some View {
        TextField("The name your buddy sees", text: $name)
            .textContentType(.givenName)
        Button("Get an invite code") { askingFirst(makeInvite) }
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
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
        } else {
            Text("Your invite is waiting for your friend.").foregroundStyle(Theme.text)
        }
    }

    @ViewBuilder
    private var paired: some View {
        if model.buddyStatus?.role == "friend" {
            Text("Your buddy: \(model.buddyStatus?.buddyName ?? "your friend")").foregroundStyle(Theme.text)
            if let note = model.buddyStatus?.notes?.first {
                Text(note.text).font(.footnote).foregroundStyle(Theme.textMuted)
            }
        } else {
            Text("Paired with your friend.").foregroundStyle(Theme.text)
        }
        Button("Unpair", role: .destructive) { confirmUnpair = true }
            .confirmationDialog("Stop sharing with your buddy?", isPresented: $confirmUnpair, titleVisibility: .visible) {
                Button("Unpair", role: .destructive) { run { await model.unpairBuddy() } }
            } message: {
                Text("Your buddy's row disappears for both of you. They aren't told.")
            }
    }

    // MARK: Actions

    /// Pairing needs uploads; with them off, ask first (BN2).
    private func askingFirst(_ action: @escaping () -> Void) {
        if model.mayUpload { action() } else { afterConsent = action }
    }

    private func makeInvite() {
        run {
            switch await model.inviteBuddy(name: name) {
            case .success(let made): invite = made
            case .failure(let failure): message = say(failure)
            }
        }
    }

    private func redeem() {
        run { message = await model.redeemBuddy(code: code).map(say) }
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
