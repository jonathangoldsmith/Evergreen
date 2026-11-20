import Foundation

/// Where the memory bundle's staged events go. Gets one batch as a JSON array
/// and answers whether the whole batch was accepted; the engine then
/// acknowledges those insert ids so they leave the outbox.
protocol EventSink: Sendable {
    func send(batch: Data) async -> Bool
}
