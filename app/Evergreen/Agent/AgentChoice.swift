import Foundation

enum AgentChoice {
    /// The harness URL from the app's page in iOS Settings; empty means the
    /// stand-in. Before uploads are allowed (BN2) it's always the stand-in,
    /// with no harness shoe pick or evidence: the snapshot carries workouts
    /// and calendar busy times, so nothing goes to the harness.
    static func current(uploadsAllowed: Bool) -> Agent {
        guard uploadsAllowed else { return StandInAgent(evidence: nil, recommend: nil) }
        let raw = UserDefaults.standard.string(forKey: "harness_url")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let url = URL(string: raw), url.scheme?.hasPrefix("http") == true {
            return HarnessAgent(baseURL: url)
        }
        return StandInAgent()
    }
}
