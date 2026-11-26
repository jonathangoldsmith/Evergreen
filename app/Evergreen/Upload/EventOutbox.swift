import Foundation
import SwiftData
import os

/// The phone's one durable queue for guardrail events (eng review D1, task
/// E6). Events wait in SwiftData until the harness returns their ids as
/// stored; anything else (offline, a 503, a 502) leaves them for next time.
@MainActor
final class EventOutbox {
    typealias Sender = @Sendable ([UploadEvent]) async throws -> [String]

    static let batchSize = 500
    private static let log = Logger(subsystem: "com.evergreentraining.app", category: "outbox")

    private let context: ModelContext
    private let sender: () -> Sender?
    private var flushing = false

    /// Whether uploads are allowed now (BN2). Read on each flush, so nothing
    /// is sent before a "yes", or after a later "Keep it on my phone".
    var isAllowed: () -> Bool = { true }

    /// `sender` is read on each flush, so setting the harness URL later starts uploads.
    init(context: ModelContext, sender: @escaping () -> Sender?) {
        self.context = context
        self.sender = sender
    }

    var pending: [OutboxEvent] {
        (try? context.fetch(FetchDescriptor<OutboxEvent>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    /// Queues an event. The same id replaces its waiting copy (a week's counts).
    func enqueue(_ event: UploadEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        if let waiting = pending.first(where: { $0.eventId == event.id }) {
            waiting.data = data
        } else {
            context.insert(OutboxEvent(eventId: event.id, data: data, createdAt: Date()))
        }
        try? context.save()
    }

    /// Drops everything waiting: declining uploads leaves the outbox empty (BN2).
    func clear() {
        pending.forEach(context.delete)
        try? context.save()
    }

    /// Sends what's waiting, oldest first, and drops only the acknowledged ids.
    @discardableResult
    func flush() async -> Int {
        guard !flushing, isAllowed(), let send = sender() else { return 0 }
        flushing = true
        defer { flushing = false }
        var acknowledged = 0
        while true {
            let batch = Array(pending.prefix(Self.batchSize))
            guard !batch.isEmpty else { break }
            let events = batch.compactMap { try? JSONDecoder().decode(UploadEvent.self, from: $0.data) }
            let stored: Set<String>
            do {
                stored = Set(try await send(events))
            } catch {
                Self.log.info("Outbox kept \(batch.count) events: \(String(describing: error), privacy: .public)")
                break
            }
            let done = batch.filter { stored.contains($0.eventId) }
            done.forEach(context.delete)
            try? context.save()
            acknowledged += done.count
            if done.count < batch.count { break }      // something wasn't stored; try again later
        }
        return acknowledged
    }
}
