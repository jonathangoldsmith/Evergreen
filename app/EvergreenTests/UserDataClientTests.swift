import Foundation
import Testing
@testable import Evergreen

/// UserDataClient as it behaves today (eng review D3, task E3): what's kept,
/// erasing it, and the two failures Your data shows. Written before any
/// change to it, against a fake harness, with the real request path
/// (HarnessRequest and DeviceAuth) in between.
struct UserDataClientTests {
    static let base = URL(string: "https://harness.test")!
    static let user = "usr_aaaaaaaaaaaaaaaa"

    /// A fake harness: answers by "METHOD /path", in order (the last one
    /// repeats), and records every request.
    actor FakeHarness {
        private(set) var requests: [URLRequest] = []
        private var answers: [String: [(Int, Data)]]
        var down = false

        init(_ answers: [String: [(Int, String)]]) {
            self.answers = answers.mapValues { $0.map { ($0.0, Data($0.1.utf8)) } }
        }

        func handle(_ request: URLRequest) throws -> (Data, URLResponse) {
            requests.append(request)
            if down { throw URLError(.notConnectedToInternet) }
            let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
            var queue = answers[key] ?? [(404, Data())]
            let (status, body) = queue.count > 1 ? queue.removeFirst() : queue[0]
            answers[key] = queue
            return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }

        func requests(_ key: String) -> [URLRequest] {
            requests.filter { "\($0.httpMethod ?? "GET") \($0.url?.path ?? "")" == key }
        }
    }

    static let kept = #"{"historyStored":true,"updatedAt":"2026-11-20T10:00:00Z","workouts":12,"days":28,"recommendations":3,"guardrailEvents":5}"#
    static let usersPath = "/users/\(user)"

    /// A client on the fake, with its own Keychain account so no test sees
    /// another's token or the app's.
    static func client(_ harness: FakeHarness) -> (UserDataClient, DeviceAuth) {
        let transport: HarnessRequest.Transport = { try await harness.handle($0) }
        let auth = DeviceAuth(account: "test-\(UUID().uuidString)", transport: transport)
        return (UserDataClient(baseURL: base, secret: "s3cret", user: user, transport: transport, auth: auth), auth)
    }

    @Test func keptReadsWhatTheHarnessKeepsWithTheDeviceToken() async throws {
        let harness = FakeHarness(["POST /devices": [(200, #"{"token":"tok-1"}"#)], "GET \(Self.usersPath)": [(200, Self.kept)]])
        let (client, auth) = Self.client(harness)
        defer { Task { await auth.forget() } }

        let kept = try await client.kept()
        #expect(kept == UserDataClient.Kept(historyStored: true, updatedAt: "2026-11-20T10:00:00Z", workouts: 12,
                                            days: 28, recommendations: 3, guardrailEvents: 5))
        let get = try #require(await harness.requests("GET \(Self.usersPath)").first)
        #expect(get.value(forHTTPHeaderField: "X-Harness-Secret") == "s3cret")
        #expect(get.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        #expect(get.timeoutInterval == UserDataClient.timeout)
        // Registered once, with the secret and the user.
        let register = try #require(await harness.requests("POST /devices").first)
        #expect(register.value(forHTTPHeaderField: "X-Harness-Secret") == "s3cret")
        #expect(register.httpBody.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } == ["user": Self.user])

        // A second call reuses the saved token.
        _ = try await client.kept()
        #expect(await harness.requests("POST /devices").count == 1)
    }

    @Test func anOlderHarnessWithoutGuardrailEventsStillReads() async throws {
        let old = #"{"historyStored":false,"workouts":0,"days":0,"recommendations":0}"#
        let harness = FakeHarness(["POST /devices": [(200, #"{"token":"t"}"#)], "GET \(Self.usersPath)": [(200, old)]])
        let (client, auth) = Self.client(harness)
        defer { Task { await auth.forget() } }
        let kept = try await client.kept()
        #expect(!kept.historyStored && kept.updatedAt == nil && kept.guardrailEvents == nil)
    }

    @Test func eraseSendsOneDelete() async throws {
        let harness = FakeHarness(["POST /devices": [(200, #"{"token":"t"}"#)],
                                   "DELETE \(Self.usersPath)": [(200, #"{"deleted":{"history":1}}"#)]])
        let (client, auth) = Self.client(harness)
        defer { Task { await auth.forget() } }
        try await client.erase()
        #expect(await harness.requests("DELETE \(Self.usersPath)").count == 1)
    }

    @Test func offlineIsUnreachable() async throws {
        let harness = FakeHarness([:])
        await harness.setDown()
        let (client, auth) = Self.client(harness)
        defer { Task { await auth.forget() } }
        await #expect(throws: UserDataClient.Failure.unreachable) { try await client.kept() }
        await #expect(throws: UserDataClient.Failure.unreachable) { try await client.erase() }
    }

    @Test func anErrorStatusOrABadAnswerIsRefused() async throws {
        let harness = FakeHarness(["POST /devices": [(200, #"{"token":"t"}"#)],
                                   "GET \(Self.usersPath)": [(500, "oops"), (200, "not json")],
                                   "DELETE \(Self.usersPath)": [(503, "")]])
        let (client, auth) = Self.client(harness)
        defer { Task { await auth.forget() } }
        await #expect(throws: UserDataClient.Failure.refused) { try await client.kept() }   // 500
        await #expect(throws: UserDataClient.Failure.refused) { try await client.kept() }   // 200, can't decode
        await #expect(throws: UserDataClient.Failure.refused) { try await client.erase() }  // 503
    }

    @Test func a401RegistersAgainAndRetriesOnce() async throws {
        let harness = FakeHarness(["POST /devices": [(200, #"{"token":"old"}"#), (200, #"{"token":"new"}"#)],
                                   "GET \(Self.usersPath)": [(401, ""), (200, Self.kept)]])
        let (client, auth) = Self.client(harness)
        defer { Task { await auth.forget() } }
        _ = try await client.kept()
        let gets = await harness.requests("GET \(Self.usersPath)")
        #expect(gets.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer old", "Bearer new"])
        #expect(await harness.requests("POST /devices").count == 2)
    }

    @Test func withoutADeviceTokenItStillSendsTheSecret() async throws {
        let harness = FakeHarness(["POST /devices": [(503, "")], "GET \(Self.usersPath)": [(200, Self.kept)]])
        let (client, auth) = Self.client(harness)
        defer { Task { await auth.forget() } }
        _ = try await client.kept()
        let get = try #require(await harness.requests("GET \(Self.usersPath)").first)
        #expect(get.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(get.value(forHTTPHeaderField: "X-Harness-Secret") == "s3cret")
    }
}

extension UserDataClientTests.FakeHarness {
    func setDown() { down = true }
}
