import Foundation

/// Posts staged events to Amplitude's HTTP V2 API. The events come from the
/// memory bundle already shaped and checked (memory-agent/docs/AMPLITUDE.md):
/// opaque ids, no names or health readings. Amplitude drops repeats by
/// `insert_id`, so a batch sent twice after a lost reply counts once.
struct AmplitudeSink: EventSink {
    let apiKey: String

    static let endpoint = URL(string: "https://api2.amplitude.com/2/httpapi")!

    /// The API key from the app's page in iOS Settings; empty means no sending.
    /// The key never lives in the repo.
    static func configured() -> AmplitudeSink? {
        let key = UserDefaults.standard.string(forKey: "amplitude_api_key")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return key.isEmpty ? nil : AmplitudeSink(apiKey: key)
    }

    func send(batch: Data) async -> Bool {
        guard let events = try? JSONSerialization.jsonObject(with: batch),
              let body = try? JSONSerialization.data(withJSONObject: ["api_key": apiKey, "events": events])
        else { return false }
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return false }
        return http.statusCode == 200
    }
}
