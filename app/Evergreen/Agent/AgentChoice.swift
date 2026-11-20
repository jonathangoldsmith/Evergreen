import Foundation

enum AgentChoice {
    /// The harness URL from the app's page in iOS Settings; empty means the stand-in.
    static func current() -> Agent {
        let raw = UserDefaults.standard.string(forKey: "harness_url")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let url = URL(string: raw), url.scheme?.hasPrefix("http") == true {
            return HarnessAgent(baseURL: url)
        }
        return StandInAgent()
    }
}
