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
        Section {
            TextField("The name your coach sees", text: $name)
                .textContentType(.givenName)
                // On one row: a modifier on the Section would run once per row.
                .task { await load() }
            Toggle(isOn: $includeFeelings) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include how I've felt").foregroundStyle(Theme.text)
                    Text("Weekly pain answers and sore or tired days.")
                        .font(.footnote).foregroundStyle(Theme.textMuted)
                }
            }
            Button("Make a link for my coach", action: create)
                .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
            if let newLink {
                ShareLink(item: newLink, message: Text("My training from Evergreen, read-only.")) {
                    Label("Send the link", systemImage: "square.and.arrow.up")
                }
            }
            ForEach(shares.filter { $0.state != "revoked" }) { share in
                row(share)
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(Theme.textMuted)
            }
        } header: {
            Text("Coach links")
        } footer: {
            Text("Your coach sees the runs Evergreen changed and why, and your weeks in range. Never your Apple Health data, calendar titles or injuries.")
        }
        .listRowBackground(Theme.card)
    }

    /// One shared link: who, until when, what it includes, and Renew or Revoke.
    private func row(_ share: CoachClient.Share) -> some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Text(share.state == "expired" ? "\(share.displayName) · expired" : "\(share.displayName) · until \(expiry(share))")
                .foregroundStyle(Theme.text)
            Toggle("Include how I've felt", isOn: Binding(get: { share.includeFeelings }, set: { on in
                run { _ = try await model.coachClient?.update(share.id, includeFeelings: on) }
            }))
            .font(.footnote)
            // Two buttons in one Form row: borderless, so each takes its own tap.
            HStack(spacing: Theme.lg) {
                Button("Renew 90 days") { run { _ = try await model.coachClient?.update(share.id, renew: true) } }
                Button("Revoke", role: .destructive) { run { try await model.coachClient?.revoke(share.id) } }
            }
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
        }
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
