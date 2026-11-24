import Foundation
import SwiftData

/// The person's own settings that outlive any story day: the injury month,
/// which calendars hold their training plan, consent, and which onboarding
/// steps they've seen. One row per install.
@Model
final class Profile {
    /// The month of the most recent injury, from onboarding or a "Yes" pain answer (X9).
    var injuryMonth: Date?
    /// Whether the injury question was answered (No counts).
    var injuryAnswered: Bool = false
    /// Picked training calendars' identifiers, one per line.
    var trainingCalendarText: String = ""
    /// Whether the training-calendar step was done (picking none counts).
    var trainingCalendarsPicked: Bool = false
    /// "What leaves your phone" (BN2): nil until asked.
    var uploadsAllowed: Bool?
    /// The research opt-in, off by default (BN2).
    var researchAllowed: Bool = false
    var consentVersion: Int?
    var consentAt: Date?
    /// The newest onboarding this install has finished (eng re-run R8).
    var onboardingVersion: Int = 0
    /// Days the app was opened (yyyy-MM-dd, one per line, last 14), so the
    /// range report can count a rest day the person checked in on (item 18).
    var openedDaysText: String = ""

    init() {}

    var trainingCalendarIds: Set<String> {
        get { Set(trainingCalendarText.split(separator: "\n").map(String.init)) }
        set { trainingCalendarText = newValue.sorted().joined(separator: "\n") }
    }
}
