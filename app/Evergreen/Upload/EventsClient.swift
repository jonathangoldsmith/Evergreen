import Foundation

/// `POST /users/{id}/events` on the harness (eng review D1). Uses the
/// planner's URL and secret. Returns the ids the harness stored.
struct EventsClient: Sendable {
    let baseURL: URL
    let secret: String
    let user: String

    static let timeout: TimeInterval = 15

    static func configured(user: String = DeviceIdentity.userId) -> EventsClient? {
        RecommendClient.configured().map { EventsClient(baseURL: $0.baseURL, secret: $0.secret, user: user) }
    }

    /// The outbox's sender for the harness as configured now; nil without one.
    static func currentSender() -> EventOutbox.Sender? {
        guard let client = configured() else { return nil }
        let send: EventOutbox.Sender = { events in try await client.send(events) }
        return send
    }

    enum Failure: Error { case unreachable, refused(Int) }

    private struct Body: Encodable { var events: [UploadEvent] }
    private struct Answer: Decodable { var stored: [String] }

    func request(_ events: [UploadEvent]) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "users").appending(path: user).appending(path: "events"),
                                 timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(secret, forHTTPHeaderField: "X-Harness-Secret")
        request.httpBody = try JSONEncoder().encode(Body(events: events))
        return request
    }

    func send(_ events: [UploadEvent]) async throws -> [String] {
        let answer: (Data, URLResponse)
        do { answer = try await URLSession.shared.data(for: request(events)) } catch { throw Failure.unreachable }
        let status = (answer.1 as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.refused(status) }
        return try JSONDecoder().decode(Answer.self, from: answer.0).stored
    }
}
