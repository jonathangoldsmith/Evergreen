import Foundation

/// What Evergreen's planner keeps for this install's anonymous id, and erasing
/// it (`GET` and `DELETE /users/{id}`). Uses the planner's URL and secret.
struct UserDataClient: Sendable {
    let baseURL: URL
    let secret: String
    let user: String

    static let timeout: TimeInterval = 10

    static func configured(user: String = DeviceIdentity.userId) -> UserDataClient? {
        RecommendClient.configured().map { UserDataClient(baseURL: $0.baseURL, secret: $0.secret, user: user) }
    }

    /// The harness's answer from `GET /users/{id}`.
    struct Kept: Decodable, Equatable, Sendable {
        var historyStored: Bool
        var updatedAt: String?
        var workouts: Int
        var days: Int
        var recommendations: Int
    }

    enum Failure: Error { case unreachable, refused }

    func kept() async throws(Failure) -> Kept {
        let data = try await send("GET")
        do { return try JSONDecoder().decode(Kept.self, from: data) } catch { throw .refused }
    }

    func erase() async throws(Failure) {
        _ = try await send("DELETE")
    }

    private func send(_ method: String) async throws(Failure) -> Data {
        var request = URLRequest(url: baseURL.appending(path: "users").appending(path: user), timeoutInterval: Self.timeout)
        request.httpMethod = method
        request.setValue(secret, forHTTPHeaderField: "X-Harness-Secret")
        let answer: (Data, URLResponse)
        do { answer = try await URLSession.shared.data(for: request) } catch { throw .unreachable }
        guard let http = answer.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw .refused }
        return answer.0
    }
}
