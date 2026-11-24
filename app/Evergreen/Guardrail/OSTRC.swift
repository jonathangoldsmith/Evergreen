import Foundation

/// The Oslo Sports Trauma Research Center overuse questionnaire's four
/// questions about the past week (business notes BN1). The wording here is a
/// placeholder close to the published form; the version, exact wording and
/// terms of use are confirmed with a research partner before the first cohort
/// (task B4). Codes are each option's position, 0 being no problem.
enum OSTRC {
    struct Question: Hashable, Sendable {
        var text: String
        var options: [String]
    }

    static let questions: [Question] = [
        Question(text: "Have you had any difficulties taking part in normal training because of pain or problems?",
                 options: ["Full participation without problems", "Full participation, but with problems",
                           "Reduced participation because of problems", "Cannot participate because of problems"]),
        Question(text: "To what extent have you reduced your training because of pain or problems?",
                 options: ["No reduction", "To a minor extent", "To a moderate extent", "To a major extent",
                           "Cannot participate at all"]),
        Question(text: "To what extent have pain or problems affected your performance?",
                 options: ["No effect", "To a minor extent", "To a moderate extent", "To a major extent",
                           "Cannot participate at all"]),
        Question(text: "To what extent have you had pain related to running?",
                 options: ["No pain", "Mild pain", "Moderate pain", "Severe pain"]),
    ]

    /// "No" to the one-tap question is recorded as a week with no problem.
    static let noProblem = [0, 0, 0, 0]
}
