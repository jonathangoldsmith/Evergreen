import Foundation

/// This install's own harness token (eng review D7, task E9). Registered once
/// with the shared secret (`POST /devices`), kept in the Keychain, and sent as
/// a bearer token on every `/users/{id}/...` call. The shared secret alone
/// can't read anyone's data.
actor DeviceAuth {
    static let shared = DeviceAuth()

    private let item = KeychainItem(account: "harness_device_token")
    private var registering: Task<String?, Never>?

    /// The saved token, or a new one from the harness; nil if it can't register.
    func token(baseURL: URL, secret: String, user: String) async -> String? {
        if let saved = item.read() { return saved }
        if let registering { return await registering.value }
        let task = Task { await Self.register(baseURL: baseURL, secret: secret, user: user) }
        registering = task
        let token = await task.value
        registering = nil
        if let token { item.write(token) }
        return token
    }

    /// After a 401: the harness lost the device (a cold start without SingleStore, or a DELETE).
    func forget() {
        item.delete()
    }

    private static func register(baseURL: URL, secret: String, user: String) async -> String? {
        var request = URLRequest(url: baseURL.appending(path: "devices"), timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(secret, forHTTPHeaderField: "X-Harness-Secret")
        request.httpBody = try? JSONEncoder().encode(["user": user])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let answer = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }
        return answer["token"]
    }
}
