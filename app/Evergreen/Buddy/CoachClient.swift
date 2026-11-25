import Foundation

/// The harness's coach-share routes (range plan item 20): a private,
/// read-only link for the runner's coach, its "Include how I've felt" tick,
/// renew and revoke. The link's token appears only in the answer to create.
struct CoachClient: Sendable {
    let baseURL: URL
    let secret: String
    let user: String

    static let timeout: TimeInterval = 10

    static func configured(user: String = DeviceIdentity.userId) -> CoachClient? {
        RecommendClient.configured().map { CoachClient(baseURL: $0.baseURL, secret: $0.secret, user: user) }
    }

    struct Share: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var displayName: String
        var includeFeelings: Bool
        var expiresAt: String
        /// active, expired or revoked.
        var state: String
        /// Only in the answer to create.
        var token: String?
    }

    private struct ShareList: Decodable { var shares: [Share] }

    /// The page a coach opens: `<harness>/coach/<token>`.
    func link(for token: String) -> URL {
        baseURL.appending(path: "coach").appending(path: token)
    }

    func create(name: String, includeFeelings: Bool) async throws(BuddyClient.Failure) -> Share {
        try await call("POST", "coach-shares", ["displayName": .string(name), "includeFeelings": .bool(includeFeelings)])
    }

    func list() async throws(BuddyClient.Failure) -> [Share] {
        let answer: ShareList = try await call("GET", "coach-shares")
        return answer.shares
    }

    func update(_ id: String, includeFeelings: Bool? = nil, renew: Bool = false) async throws(BuddyClient.Failure) -> Share {
        var body: [String: Value] = ["renew": .bool(renew)]
        if let includeFeelings { body["includeFeelings"] = .bool(includeFeelings) }
        return try await call("PATCH", "coach-shares/\(id)", body)
    }

    func revoke(_ id: String) async throws(BuddyClient.Failure) {
        let _: [String: Bool] = try await call("DELETE", "coach-shares/\(id)")
    }

    enum Value: Encodable, Sendable {
        case string(String)
        case bool(Bool)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            }
        }
    }

    func request(_ method: String, _ path: String, _ body: [String: Value]? = nil) -> URLRequest {
        var url = baseURL.appending(path: "users").appending(path: user)
        for part in path.split(separator: "/") { url = url.appending(path: String(part)) }
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = method
        request.setValue(secret, forHTTPHeaderField: "X-Harness-Secret")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)
        }
        return request
    }

    private func call<T: Decodable>(_ method: String, _ path: String, _ body: [String: Value]? = nil) async throws(BuddyClient.Failure) -> T {
        let answer: (Data, Int)
        do {
            answer = try await HarnessRequest.send(request(method, path, body), baseURL: baseURL, secret: secret, user: user)
        } catch { throw .unreachable }
        let status = answer.1
        guard (200..<300).contains(status) else {
            let detail = (try? JSONDecoder().decode([String: String].self, from: answer.0))?["detail"]
            throw .refused(detail ?? "status_\(status)")
        }
        do { return try JSONDecoder().decode(T.self, from: answer.0) } catch { throw .refused("bad_answer") }
    }
}
