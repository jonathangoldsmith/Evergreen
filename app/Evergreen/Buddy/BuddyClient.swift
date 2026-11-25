import Foundation

/// The harness's buddy routes (range plan item 22): invite, redeem, status,
/// rename, unpair, and this device's push token. Same URL and secret as the
/// planner. Failures carry the harness's reason, so the app can say it kindly.
struct BuddyClient: Sendable {
    let baseURL: URL
    let secret: String
    let user: String

    static let timeout: TimeInterval = 10

    static func configured(user: String = DeviceIdentity.userId) -> BuddyClient? {
        RecommendClient.configured().map { BuddyClient(baseURL: $0.baseURL, secret: $0.secret, user: user) }
    }

    struct Note: Codable, Hashable, Sendable {
        var text: String
        var at: String
    }

    struct Status: Codable, Hashable, Sendable {
        /// none, invited or paired.
        var status: String
        var role: String?
        var buddyName: String?
        var yourName: String?
        var expiresAt: String?
        var notes: [Note]?
    }

    struct Invite: Codable, Hashable, Sendable {
        var code: String
        var expiresAt: String
    }

    enum Failure: Error, Equatable {
        case unreachable
        /// The harness's reason: own_code, used, expired, already_paired, unknown_code, too_many_tries, bad_name.
        case refused(String)
    }

    func status() async throws(Failure) -> Status { try await call("GET", "buddy") }
    func invite(name: String) async throws(Failure) -> Invite { try await call("POST", "buddy", ["displayName": name]) }
    func redeem(code: String) async throws(Failure) -> Status { try await call("POST", "buddy/redeem", ["code": code]) }
    func rename(_ name: String) async throws(Failure) -> Status { try await call("PATCH", "buddy", ["displayName": name]) }
    func unpair() async throws(Failure) -> Status { try await call("DELETE", "buddy") }

    func savePushToken(_ token: String, environment: String) async throws(Failure) {
        let _: [String: Bool] = try await call("PUT", "push-token", ["token": token, "environment": environment])
    }

    func request(_ method: String, _ path: String, _ body: [String: String]? = nil) -> URLRequest {
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

    private func call<T: Decodable>(_ method: String, _ path: String, _ body: [String: String]? = nil) async throws(Failure) -> T {
        let answer: (Data, URLResponse)
        do { answer = try await URLSession.shared.data(for: request(method, path, body)) } catch { throw .unreachable }
        let status = (answer.1 as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSONDecoder().decode([String: String].self, from: answer.0))?["detail"]
            throw .refused(detail ?? "status_\(status)")
        }
        do { return try JSONDecoder().decode(T.self, from: answer.0) } catch { throw .refused("bad_answer") }
    }
}
