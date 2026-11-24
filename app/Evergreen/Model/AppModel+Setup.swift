import Foundation

/// The range setup steps (plan item 4, business notes BN2, eng re-run R8):
/// what leaves the phone, training calendars, and the injury question. New
/// installs see them after Permissions; people who onboarded before them see
/// them once, full screen, with "Not now" allowed once.
extension AppModel {
    /// Bump when onboarding gains a step existing users should see.
    static let onboardingVersion = 1
    /// The consent screen's wording version, stored with each answer.
    static let consentVersion = 1
    private static let deferredKey = "range_setup_deferred_version"

    /// An existing user who hasn't seen the newest steps.
    var needsRangeSetup: Bool {
        onboarded && profile.onboardingVersion < Self.onboardingVersion && !rangeSetupDeferredThisLaunch
    }

    /// "Not now" is offered once per onboarding version.
    var canDeferRangeSetup: Bool {
        UserDefaults.standard.integer(forKey: Self.deferredKey) < Self.onboardingVersion
    }

    func deferRangeSetup() {
        UserDefaults.standard.set(Self.onboardingVersion, forKey: Self.deferredKey)
        rangeSetupDeferredThisLaunch = true
    }

    func finishRangeSetup() {
        profile.onboardingVersion = Self.onboardingVersion
        save()
    }

    // MARK: What leaves your phone (BN2)

    func setConsent(uploads: Bool, research: Bool) {
        profile.uploadsAllowed = uploads
        // Research use needs uploads; it's never on without them.
        profile.researchAllowed = uploads && research
        profile.consentVersion = Self.consentVersion
        profile.consentAt = Date()
        save()
        // A "no" never leaves the phone; a "yes" is the first event sent.
        if uploads {
            upload(.consent(research: profile.researchAllowed, version: Self.consentVersion, at: Date(), calendar: calendar), ownAnswer: true)
        }
    }

    // MARK: Training calendars (item 1)

    func trainingCalendarOptions() -> [TrainingCalendarOption] {
        calendarSync.trainingCalendarOptions()
    }

    func setTrainingCalendars(_ ids: Set<String>) {
        profile.trainingCalendarIds = ids
        profile.trainingCalendarsPicked = true
        save()
        Task { await tick() }
    }

    // MARK: Injury (items 4 and 5)

    /// "Any injury in the last 12 months?" Nil is No; otherwise roughly when.
    func setInjury(month: Date?) {
        profile.injuryMonth = month.map { calendar.dateInterval(of: .month, for: $0)?.start ?? $0 }
        profile.injuryAnswered = true
        save()
        upload(.injury(month: profile.injuryMonth, at: Date(), calendar: calendar), ownAnswer: true)
    }
}
