import Foundation
import Testing
@testable import TrackerPlusPlus

/// The memory bundle running in JavaScriptCore: a sync rolls memory, stages
/// Amplitude events and delivers them once. No network: a recording sink.
struct MemoryEngineTests {
    /// The parts of a sent event the tests look at.
    struct Sent: Sendable {
        var type: String?
        var user: String?
        var activity: String?
        var source: String?
        var minutes: Double?
    }

    actor RecordingSink: EventSink {
        var accept: Bool
        private(set) var events: [Sent] = []

        init(accept: Bool = true) { self.accept = accept }

        func send(batch: Data) async -> Bool {
            guard accept else { return false }
            let raw = (try? JSONSerialization.jsonObject(with: batch) as? [[String: Any]]) ?? []
            events += raw.map { event in
                let props = event["event_properties"] as? [String: Any] ?? [:]
                return Sent(type: event["event_type"] as? String, user: event["user_id"] as? String,
                            activity: props["activity"] as? String, source: props["source"] as? String,
                            minutes: props["minutes"] as? Double)
            }
            return true
        }

        func setAccept(_ value: Bool) { accept = value }
        var types: [String] { events.compactMap(\.type) }
    }

    static func engine() throws -> MemoryEngine {
        let root = FileManager.default.temporaryDirectory.appending(path: "memory-\(UUID().uuidString)")
        return try #require(MemoryEngine(root: root, secret: "test-secret-0123456789abcdef"))
    }

    static func jordan(now: Date = Fixture.at(13, 30)) -> MemoryInput {
        let person = Persona.load(.jordan, storyDay: Fixture.storyDay, calendar: Fixture.calendar)
        return MemoryInput(personaKey: "jordan", historyStart: person.historyStart, now: now,
                           workouts: person.workouts, calendar: Fixture.calendar)
    }

    @Test func syncSendsWorkoutsAndTheRolledDayOnce() async throws {
        let engine = try Self.engine()
        let sink = RecordingSink()
        let input = Self.jordan()
        let counted = input.workouts.filter { $0.minutes >= 10 }.count

        let first = await engine.sync(input, sink: sink)
        #expect(first.problem == nil)
        #expect(first.pending == 0)
        let types = await sink.types
        #expect(types.filter { $0 == "workout_completed" }.count == counted)
        #expect(types.filter { $0 == "memory_rolled" }.count == 1)
        #expect(first.sent == types.count)

        let user = await engine.userId("jordan")
        let events = await sink.events
        #expect(events.allSatisfy { $0.user == user })

        // Nothing changed, so nothing new is staged.
        let second = await engine.sync(input, sink: sink)
        #expect(second.sent == 0)
        #expect(second.problem == nil)
    }

    @Test func aRefusedBatchWaitsAndGoesOutNextTime() async throws {
        let engine = try Self.engine()
        let sink = RecordingSink(accept: false)

        let refused = await engine.sync(Self.jordan(), sink: sink)
        #expect(refused.sent == 0)
        #expect(refused.pending > 0)
        #expect(refused.problem != nil)

        await sink.setAccept(true)
        let delivered = await engine.sync(Self.jordan(), sink: sink)
        #expect(delivered.pending == 0)
        #expect(delivered.sent > 0)
        #expect(await sink.types.contains("workout_completed"))
    }

    @Test func aLoggedWorkoutIsSentAfterTheFirstSync() async throws {
        let engine = try Self.engine()
        let sink = RecordingSink()
        var input = Self.jordan(now: Fixture.at(18, 50))
        _ = await engine.sync(input, sink: sink)
        let before = await sink.events.count

        input.workouts.append(Workout(id: "demo-walk", activityType: "Walking", start: Fixture.at(18, 30),
                                      end: Fixture.at(18, 45), effort: 4, avgHeartRate: nil, source: .demo))
        let report = await engine.sync(input, sink: sink)

        #expect(report.sent == 1)
        let last = try #require(await sink.events.last)
        #expect(await sink.events.count == before + 1)
        #expect(last.type == "workout_completed")
        #expect(last.activity == "Walking")
        #expect(last.source == "manual")
        #expect(last.minutes == 15)
    }

    @Test func withoutAKeyMemoryStillRollsAndNothingIsStaged() async throws {
        let engine = try Self.engine()
        let report = await engine.sync(Self.jordan(), sink: nil)
        #expect(report.problem == nil)
        #expect(report.sent == 0)
        #expect(report.pending == 0)
    }
}
