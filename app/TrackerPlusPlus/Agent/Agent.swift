import Foundation

/// Whatever answers `/tick`: the deployed harness, or the offline stand-in.
protocol Agent: Sendable {
    var name: String { get }
    func tick(_ snapshot: TickSnapshot) async throws -> TickResponse
}
