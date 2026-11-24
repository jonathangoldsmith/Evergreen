import Foundation
import SwiftData
import Testing
@testable import Evergreen

/// The upload outbox (eng review D1, task E6), the events' privacy rules
/// (plan item 9) and the Amplitude list (task T7).
@MainActor
struct EventOutboxTests {
    static var containers: [ModelContainer] = []

    static func context() throws -> ModelContext {
        let container = try Storage.open(at: StorageTests.tempStore())
        containers.append(container)
        return container.mainContext
    }

    /// A fake harness: offline until `online`, then stores what it's sent, once per id.
    final class FakeHarness: @unchecked Sendable {
        var online = false
        var storedIds: [String] = []
        var calls = 0

        func send(_ events: [UploadEvent]) async throws -> [String] {
            calls += 1
            guard online else { throw EventsClient.Failure.unreachable }
            for event in events where !storedIds.contains(event.id) { storedIds.append(event.id) }
            return events.map(\.id)
        }
    }

    static let run = GuardrailCopyTests.run
    static let flag = GuardrailCopyTests.flags[0]

    @Test func offlineThenOnlineEachEventLandsOnce() async throws {
        let harness = FakeHarness()
        let outbox = EventOutbox(context: try Self.context()) { { try await harness.send($0) } }
        let at = Fixture.at(19)
        outbox.enqueue(.flag(Self.flag, run: Self.run, at: at, calendar: Fixture.calendar))
        outbox.enqueue(.checkIn(.sore, run: Self.run, at: at, calendar: Fixture.calendar))

        #expect(await outbox.flush() == 0)
        #expect(outbox.pending.count == 2)

        harness.online = true
        #expect(await outbox.flush() == 2)
        #expect(await outbox.flush() == 0)
        #expect(outbox.pending.isEmpty)
        #expect(harness.storedIds.count == 2)
    }

    @Test func onlyAcknowledgedIdsLeaveTheOutbox() async throws {
        let outbox = EventOutbox(context: try Self.context()) { { events in [events[0].id] } }
        let week = Fixture.storyDay
        outbox.enqueue(.pain(.no, ostrc: OSTRC.noProblem, week: week, at: Fixture.at(18), calendar: Fixture.calendar))
        outbox.enqueue(.consent(research: false, version: 1, at: Fixture.at(9), calendar: Fixture.calendar))
        await outbox.flush()
        #expect(outbox.pending.count == 1)
    }

    @Test func withoutAHarnessNothingIsSentAndNothingIsLost() async throws {
        let outbox = EventOutbox(context: try Self.context()) { nil }
        outbox.enqueue(.consent(research: true, version: 1, at: Fixture.at(9), calendar: Fixture.calendar))
        #expect(await outbox.flush() == 0)
        #expect(outbox.pending.count == 1)
    }

    @Test func theSameIdReplacesItsWaitingCopy() throws {
        let outbox = EventOutbox(context: try Self.context()) { nil }
        let week = Fixture.storyDay
        outbox.enqueue(.pain(.aLittle, ostrc: nil, week: week, at: Fixture.at(18), calendar: Fixture.calendar))
        outbox.enqueue(.pain(.yes, ostrc: nil, week: week, at: Fixture.at(18), calendar: Fixture.calendar))
        #expect(outbox.pending.count == 1)
    }

    // MARK: What leaves the phone (item 9)

    @Test func eventsCarryNoTitleOrLocation() throws {
        let at = Fixture.at(19)
        let events: [UploadEvent] = [
            .flag(Self.flag, run: Self.run, at: at, calendar: Fixture.calendar),
            .choice("accept", kind: .spike, run: Self.run, at: at, calendar: Fixture.calendar),
            .checkIn(.sore, run: Self.run, at: at, calendar: Fixture.calendar),
            .pain(.yes, ostrc: [2, 1, 1, 2], week: Fixture.storyDay, at: at, calendar: Fixture.calendar),
            .injury(month: Fixture.storyDay, at: at, calendar: Fixture.calendar),
        ]
        for event in events {
            let json = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
            #expect(!json.contains("Long run"), "\(json)")
            #expect(!json.contains("Runna"), "\(json)")
            #expect(!json.lowercased().contains("knee"), "\(json)")
        }
        #expect(events[1].run == Self.run.swapItemId)
    }

    @Test func painEventsAreTheOneTapThenTheFullAnswer() {
        let week = Fixture.storyDay
        let tap = UploadEvent.pain(.aLittle, ostrc: nil, week: week, at: Fixture.at(18), calendar: Fixture.calendar)
        let full = UploadEvent.pain(.aLittle, ostrc: [1, 1, 0, 1], week: week, at: Fixture.at(18), calendar: Fixture.calendar)
        #expect(tap.id == "pain-2026-11-19-1" && full.id == "pain-2026-11-19-2")
        #expect(tap.ostrc == nil && full.ostrc == [1, 1, 0, 1])
    }

    @Test func theRequestGoesToTheUsersEventsRoute() throws {
        let client = EventsClient(baseURL: URL(string: "https://harness.example")!, secret: "s", user: "usr_0123456789abcdef")
        let request = try client.request([.consent(research: false, version: 1, at: Fixture.at(9), calendar: Fixture.calendar)])
        #expect(request.url?.absoluteString == "https://harness.example/users/usr_0123456789abcdef/events")
        #expect(request.httpMethod == "POST" && request.value(forHTTPHeaderField: "X-Harness-Secret") == "s")
        let body = try #require(request.httpBody)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let first = try #require((object["events"] as? [[String: Any]])?.first)
        #expect(first["type"] as? String == "consent" && first["uploads"] as? Bool == true)
        #expect(first["kind"] == nil)                          // unset fields aren't sent
    }

    // MARK: Amplitude (task T7)

    @Test func noAmplitudeEventCarriesAHealthValue() {
        let events: [AnalyticsEvent] = [
            .flagShown(.spike), .flagShown(.returnSpike), .flagShown(.sore), .flagShown(.tired),
            .choice("accept"), .choice("keep"), .choice("undo"), .choice("sore"),
            .painCheckIn(answered: true), .painCheckIn(answered: false),
            .backtestCompleted(answered: 6), .rangeReportViewed,
        ]
        let allowedKeys: Set<String> = ["kind", "choice", "answered"]
        for event in events {
            #expect(Set(event.properties.keys).isSubset(of: allowedKeys))
            for value in event.properties.values {
                #expect(!["sore", "tired", "yes", "aLittle", "a little", "km", "min"].contains { value.lowercased().contains($0) },
                        "\(event.name): \(value)")
            }
        }
    }
}
