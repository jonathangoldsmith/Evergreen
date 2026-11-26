import Foundation

/// The one way the phone calls the harness's per-user routes (eng review D2
/// task E4, and D7 task E9): the device token as a bearer header, plus the
/// shared secret for harnesses deployed before per-device auth. On a 401 it
/// registers again once and retries.
enum HarnessRequest {
    /// How a request reaches the network; tests pass a fake (eng review D3, task E3).
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let urlSession: Transport = { try await URLSession.shared.data(for: $0) }

    static func send(_ request: URLRequest, baseURL: URL, secret: String, user: String,
                     transport: Transport = urlSession, auth: DeviceAuth = .shared) async throws -> (Data, Int) {
        let (data, status) = try await attempt(request, baseURL: baseURL, secret: secret, user: user,
                                               transport: transport, auth: auth)
        guard status == 401 else { return (data, status) }
        await auth.forget()
        return try await attempt(request, baseURL: baseURL, secret: secret, user: user, transport: transport, auth: auth)
    }

    private static func attempt(_ request: URLRequest, baseURL: URL, secret: String, user: String,
                                transport: Transport, auth: DeviceAuth) async throws -> (Data, Int) {
        var request = request
        request.setValue(secret, forHTTPHeaderField: "X-Harness-Secret")
        if let token = await auth.token(baseURL: baseURL, secret: secret, user: user) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await transport(request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
