import Foundation

/// Asks the harness's `POST /shoes/recommend` for Jordan's next pair
/// (harness/INTEGRATION.md): real shoes from review sites, ranked and picked on
/// Superlinked SIE, cited by Senso, logged in SingleStore. It answers in the
/// app's own `Purchase` shape. Swift keeps approval, ids, break-in runs and the
/// calendar; any failure, or no answer within 6 seconds, means the stand-in's
/// own pick runs instead.
struct RecommendClient: Sendable {
    let baseURL: URL
    let secret: String

    static let timeout: TimeInterval = 6
    static let defaultURL = URL(string: "https://trackerplusplus-harness.vercel.app")!

    /// Configured once there's a shared secret: from the app's page in iOS
    /// Settings, else built in from the git-ignored `app/Secrets.xcconfig`
    /// (`HARNESS_SECRET`). The URL defaults to the deployed harness.
    static func configured(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> RecommendClient? {
        func trimmed(_ value: String?) -> String {
            value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        var secret = trimmed(defaults.string(forKey: "harness_secret"))
        if secret.isEmpty {
            let built = trimmed(bundle.object(forInfoDictionaryKey: "HARNESS_SECRET") as? String)
            if !built.hasPrefix("$(") { secret = built }
        }
        guard !secret.isEmpty else { return nil }

        let raw = trimmed(defaults.string(forKey: "recommend_url"))
        let url = raw.isEmpty ? defaultURL : URL(string: raw)
        guard let url, url.scheme?.hasPrefix("http") == true else { return nil }
        return RecommendClient(baseURL: url, secret: secret)
    }

    private struct Request: Encodable {
        struct Shoes: Encodable {
            var boughtOn: String
            var startMiles: Int
        }

        var persona: String
        /// The demo clock with the person's UTC offset: the harness counts
        /// delivery days from midnight in that offset.
        var now: String
        var shoes: Shoes
        var raceDate: String
        var mandate: [Mandate]
    }

    /// Only `purchase` matters; `condition`, `profile`, `auditId` and the rest are ignored.
    private struct Response: Decodable {
        var purchase: Purchase?
    }

    /// The harness's pick, or nil when it says the pair is fresh, or on any
    /// failure or timeout (the caller keeps its own pick).
    func shoes(persona: String, now: Date, boughtOn: Date, startMiles: Int, raceDate: Date,
               mandate: [Mandate], cal: Calendar) async -> Purchase? {
        var request = URLRequest(url: baseURL.appending(path: "shoes/recommend"), timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(secret, forHTTPHeaderField: "X-Harness-Secret")
        do {
            request.httpBody = try JSONEncoder.contract.encode(Request(
                persona: persona, now: Self.instant(now, cal),
                shoes: .init(boughtOn: Self.day(boughtOn, cal), startMiles: startMiles),
                raceDate: Self.day(raceDate, cal), mandate: mandate
            ))
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return try JSONDecoder.contract.decode(Response.self, from: data).purchase
        } catch {
            return nil
        }
    }

    /// ISO 8601 with the calendar's offset (`2026-11-19T09:00:00-08:00`), not UTC.
    static func instant(_ date: Date, _ cal: Calendar) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = cal.timeZone
        return formatter.string(from: date)
    }

    /// A local calendar day as `YYYY-MM-DD`, in the person's calendar, not UTC.
    static func day(_ date: Date, _ cal: Calendar) -> String {
        let parts = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
