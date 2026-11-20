import AmplitudeSwift
import Foundation

/// Hands the memory bundle's staged events to the app's Amplitude client, as
/// memory-agent/docs/AMPLITUDE.md describes: the SDK queues and retries them,
/// so a batch counts as accepted once it's queued. The events come shaped and
/// checked (opaque `usr_` ids, no names or health readings) and keep their own
/// `user_id`, `insert_id` and time; Amplitude drops repeats by `insert_id`.
struct AmplitudeSink: EventSink, @unchecked Sendable {
    // The SDK's client is thread-safe; it isn't marked Sendable.
    let amplitude: Amplitude

    func send(batch: Data) async -> Bool {
        guard let events = try? JSONSerialization.jsonObject(with: batch) as? [[String: Any]] else { return false }
        for event in events {
            guard let type = event["event_type"] as? String else { return false }
            amplitude.track(event: BaseEvent(
                userId: event["user_id"] as? String,
                timestamp: (event["time"] as? NSNumber)?.int64Value,
                insertId: event["insert_id"] as? String,
                eventType: type,
                eventProperties: event["event_properties"] as? [String: Any]
            ))
        }
        return true
    }
}
