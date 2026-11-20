import Foundation

/// Calls the harness's `POST /tick`.
// gstack-shortcut(dec-7cd83254): no auth, upgrade when real Health data is sent
struct HarnessAgent: Agent {
    let baseURL: URL

    var name: String { baseURL.host() ?? baseURL.absoluteString }

    func tick(_ snapshot: TickSnapshot) async throws -> TickResponse {
        var request = URLRequest(url: baseURL.appending(path: "tick"), timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.contract.encode(snapshot)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder.contract.decode(TickResponse.self, from: data)
    }
}
