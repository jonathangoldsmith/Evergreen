import Foundation

/// Asks the harness's `POST /evidence` for Senso's cited passages behind a
/// purchase. The Senso key stays on the harness; the phone only sends a query.
/// Any failure, or no answer within 3 seconds, means the caller falls back to
/// the bundled passages marked "cached" (eng review D4).
struct EvidenceClient: Sendable {
    let baseURL: URL

    static let timeout: TimeInterval = 3

    /// The evidence URL from the app's page in iOS Settings; empty means none.
    static func configured() -> EvidenceClient? {
        let raw = UserDefaults.standard.string(forKey: "evidence_url")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: raw), url.scheme?.hasPrefix("http") == true else { return nil }
        return EvidenceClient(baseURL: url)
    }

    private struct Request: Encodable {
        var purchaseKind: String
        var query: String
    }

    private struct Response: Decodable {
        var evidence: [Purchase.Evidence]
        var live: Bool
    }

    /// Live passages, or nil when the harness, Senso or the network can't answer in time.
    func passages(kind: String, query: String) async -> [Purchase.Evidence]? {
        var request = URLRequest(url: baseURL.appending(path: "evidence"), timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder.contract.encode(Request(purchaseKind: kind, query: query))
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let answer = try JSONDecoder.contract.decode(Response.self, from: data)
            return answer.live && !answer.evidence.isEmpty ? answer.evidence : nil
        } catch {
            return nil
        }
    }
}
