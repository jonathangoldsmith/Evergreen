import SwiftUI

/// The buddy's friend's short path (range plan item 22): the disclaimer,
/// notifications, what's shared, and the code. No backtest or injury question
/// unless they later set Evergreen up for themselves.
struct FriendSetupView: View {
    let onBack: () -> Void

    @Environment(AppModel.self) private var model
    @State private var code = ""
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Back", systemImage: "chevron.left", action: onBack)
                .foregroundStyle(Theme.textMuted)
                .frame(minHeight: 44)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.md) {
                    Text("Join your friend")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Text("You'll get a short note when your friend finishes a workout, like \"Alex did a 15-minute walk.\" Never a miss.")
                        .font(.body)
                        .foregroundStyle(Theme.text)
                    PermissionRow(symbol: "bell", title: "Notifications", detail: "So your friend's notes reach you.",
                                  state: model.notificationAccess == .on ? .on : model.notificationAccess == .notAsked ? .ask : .off,
                                  action: { Task { await model.requestNotificationAccess() } })
                    Text("To get notes, this phone sends a push token to Evergreen under an anonymous ID. No name or email. Unpair any time in Your data.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                    TextField("Your friend's 8-character code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .padding(.horizontal, Theme.sm)
                        .frame(minHeight: 44)
                        .overlay { RoundedRectangle(cornerRadius: Theme.radiusButton).strokeBorder(Theme.rule) }
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(Theme.textMuted)
                    }
                    Text("Evergreen suggests training changes. It isn't medical advice; see a physio or doctor for pain or injury.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.top, Theme.md)
            }
            Button("Pair with my friend", action: pair)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || code.trimmingCharacters(in: .whitespaces).count != 8)
                .padding(.top, Theme.md)
        }
        .padding(.horizontal, Theme.md)
        .padding(.bottom, Theme.lg)
        .background(Theme.surface)
    }

    private func pair() {
        busy = true
        message = nil
        Task {
            if let failure = await model.redeemBuddy(code: code) {
                switch failure {
                case .unreachable: message = BuddyCopy.unreachable
                case .refused(let reason): message = BuddyCopy.refusal(reason)
                }
            } else {
                model.finishFriendSetup()
            }
            busy = false
        }
    }
}
