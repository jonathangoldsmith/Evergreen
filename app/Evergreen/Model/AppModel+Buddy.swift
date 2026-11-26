import Foundation

/// The accountability buddy (range plan item 22): pairing through the
/// harness, the friend's notes, and this device's push token. Sharing needs
/// uploads (BN2), so it asks first when they're off.
extension AppModel {
    private static let sharedWorkoutsKey = "buddy_shared_workouts"
    private static let invitePromptDismissedKey = "buddy_invite_dismissed"

    /// Push-side people (range plan item 10) get the quiet invite line on Today.
    var showsBuddyInvite: Bool {
        guard let normal else { return false }
        let pushed = normal.gettingToKnowYou || normal.perWeek <= StandInAgent.pushPerWeek
        return pushed && buddyStatus?.status != "paired"
            && !UserDefaults.standard.bool(forKey: Self.invitePromptDismissedKey)
    }

    func dismissBuddyInvite() {
        UserDefaults.standard.set(true, forKey: Self.invitePromptDismissedKey)
        buddyStatus = buddyStatus   // redraw
    }

    func refreshBuddy() async {
        // Asking the harness for the buddy's status sends the anonymous ID (BN2).
        guard mayUpload, let client = BuddyClient.configured() else { return }
        if let status = try? await client.status() {
            buddyStatus = status
            // The token can change; a paired person sends the current one each launch.
            if status.status == "paired" { registerForPush() }
        }
    }

    /// Returns the new code, or the reason it couldn't be made.
    func inviteBuddy(name: String) async -> Result<BuddyClient.Invite, BuddyClient.Failure> {
        guard mayUpload else { return .failure(.refused("uploads_off")) }
        guard let client = BuddyClient.configured() else { return .failure(.refused("status_503")) }
        do {
            let invite = try await client.invite(name: name)
            await refreshBuddy()
            return .success(invite)
        } catch {
            return .failure(error)
        }
    }

    func redeemBuddy(code: String) async -> BuddyClient.Failure? {
        guard mayUpload else { return .refused("uploads_off") }
        guard let client = BuddyClient.configured() else { return .refused("status_503") }
        do {
            buddyStatus = try await client.redeem(code: code)
            track(.buddy("paired"))
            registerForPush()
            return nil
        } catch {
            return error
        }
    }

    func unpairBuddy() async {
        guard let client = BuddyClient.configured() else { return }
        if let status = try? await client.unpair() {
            buddyStatus = status
            track(.buddy("unpaired"))
        }
    }

    /// The coach-share client, when the harness is set up (range plan item 20).
    /// Nil with uploads off (BN2), so the section neither lists nor makes links.
    var coachClient: CoachClient? { mayUpload ? CoachClient.configured() : nil }

    /// Sharing uploads a push token, workouts or a coach's page, so it needs
    /// uploads on. Called only from "Allow and share" (`uploadConsentAlert`).
    func allowUploadsForSharing() {
        if profile.uploadsAllowed != true { setConsent(uploads: true, research: profile.researchAllowed) }
    }

    // MARK: Push token

    /// Asks iOS for a push token; `pushTokenArrived` gets it.
    func registerForPush() {
        PushRegistration.register()
    }

    /// The token goes to the harness with its environment: sandbox for builds
    /// from Xcode, production for TestFlight (item 22).
    func pushTokenArrived(_ token: Data) async {
        guard mayUpload, let client = BuddyClient.configured() else { return }
        let hex = token.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        try? await client.savePushToken(hex, environment: environment)
    }

    // MARK: The inviter's workouts

    /// Each finished workout of a paired inviter goes up once as
    /// `workout_completed` (type and rounded minutes only), which sends the
    /// friend a note. Called on every Health read, including the background
    /// wake from HealthKit's observer, so a late wake still sends it.
    func shareFinishedWorkouts() {
        guard persona.key.isReal, buddyStatus?.status == "paired", buddyStatus?.role == "inviter" else { return }
        let since = Date().addingTimeInterval(-2 * 86_400)
        var shared = Set(UserDefaults.standard.stringArray(forKey: Self.sharedWorkoutsKey) ?? [])
        for workout in health.workouts where workout.start > since && workout.minutes >= 10 && !shared.contains(workout.id) {
            var event = UploadEvent(id: "done-\(StableHash.hex(workout.id, length: 20))", type: "workout_completed",
                                    at: workout.end, calendar: calendar)
            event.activityType = workout.activityType
            event.minutes = Int((workout.minutes / 5).rounded() * 5)
            upload(event)
            shared.insert(workout.id)
        }
        UserDefaults.standard.set(Array(shared.suffix(100)), forKey: Self.sharedWorkoutsKey)
    }
}
