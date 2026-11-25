import SwiftUI

/// "Coach links" in Your data's People (range plan item 20, design decisions
/// 4 and 8): share a private read-only link with the name your coach sees,
/// choose whether it includes how you've felt, renew it, or revoke it.
struct CoachSection: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var includeFeelings = false
    @State private var shares: [CoachClient.Share] = []
    @State private var newLink: URL?
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Text("Coach links")
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
                .accessibilityAddTraits(.isHeader)
            Text("Your coach sees the runs Evergreen changed and why, and your weeks in range. Never your Apple Health data, calendar titles or injuries.")
            TextField("The name your coach sees", text: $name)
                .textContentType(.givenName)
                .padding(.horizontal, Theme.sm)
                .frame(minHeight: 44)
                .overlay { RoundedRectangle(cornerRadius: Theme.radiusButton).strokeBorder(Theme.rule) }
            Toggle(isOn: $includeFeelings) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include how I've felt")
                    Text("Weekly pain answers and sore or tired days.")
                        .font(.footnote).foregroundStyle(Theme.textMuted)
                }
            }
            .tint(Theme.accent)
            .padding(.trailing, Theme.xs)
            Button("Make a link for my coach", action: create)
                .buttonStyle(GhostButtonStyle())
                .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
            if let newLink {
                ShareLink(item: newLink, message: Text("My training from Evergreen, read-only.")) {
                    Label("Send the link", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(GhostButtonStyle())
            }
            ForEach(shares.filter { $0.state != "revoked" }) { share in
                row(share)
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(Theme.textMuted)
            }
        }
        .task { await load() }
    }

    private func row(_ share: CoachClient.Share) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Text(share.state == "expired" ? "\(share.displayName) · expired" : "\(share.displayName) · until \(expiry(share))")
                .font(.body)
            Toggle("Include how I've felt", isOn: Binding(get: { share.includeFeelings }, set: { on in
                run { _ = try await model.coachClient?.update(share.id, includeFeelings: on) }
            }))
            .tint(Theme.accent)
            .font(.footnote)
            .padding(.trailing, Theme.xs)
            HStack(spacing: Theme.sm) {
                Button("Renew 90 days") { run { _ = try await model.coachClient?.update(share.id, renew: true) } }
                    .buttonStyle(GhostButtonStyle())
                Button("Revoke") { run { try await model.coachClient?.revoke(share.id) } }
                    .buttonStyle(GhostButtonStyle())
            }
        }
        .padding(.vertical, Theme.xs)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    private func expiry(_ share: CoachClient.Share) -> String {
        let date = ISO8601DateFormatter.lenient.date(from: share.expiresAt)
        return date?.formatted(.dateTime.month(.abbreviated).day()) ?? "later"
    }

    private func create() {
        run {
            guard let client = model.coachClient else { return }
            model.allowUploadsForSharing()
            let made = try await client.create(name: name, includeFeelings: includeFeelings)
            if let token = made.token { newLink = client.link(for: token) }
        }
    }

    private func load() async {
        shares = (try? await model.coachClient?.list()) ?? []
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        message = nil
        Task {
            do {
                try await work()
            } catch BuddyClient.Failure.refused(let reason) {
                message = BuddyCopy.refusal(reason)
            } catch {
                message = BuddyCopy.unreachable
            }
            await load()
            busy = false
        }
    }
}
