import Foundation
import Testing
@testable import Evergreen

/// The phone's brake rule against contract/fixtures/guardrail.json, the cases
/// harness/tests/test_guardrail.py also runs, so the two can't drift (task T3).
struct GuardrailFixtureTests {
    struct File: Decodable {
        let timeZone: String
        let cases: [Case]
    }

    struct Case: Decodable, CustomTestStringConvertible, Sendable {
        struct Run: Decodable, Sendable { let start: String; let km: Double?; let minutes: Double; let hard: Bool? }
        struct Past: Decodable, Sendable { let daysBack: Int; let km: Double?; let minutes: Double?; let type: String? }
        struct Expect: Decodable, Sendable {
            let kind: String; let suggested: Double; let longest30: Double?; let keepEasy: Bool; let injuryAdjusted: Bool
        }
        let name: String
        let run: Run
        let history: [Past]
        let injuryMonth: String?
        let check: String?
        let bodyOff: Bool?
        let loadCeiling: Double?
        let expect: Expect?
        var testDescription: String { name }
    }

    static let url = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "contract/fixtures/guardrail.json")

    static let file: File = {
        let data = (try? Data(contentsOf: url)) ?? Data()
        return (try? JSONDecoder().decode(File.self, from: data)) ?? File(timeZone: "UTC", cases: [])
    }()

    @Test func theFixturesLoad() {
        #expect(Self.file.cases.count >= 12)
    }

    @Test(arguments: file.cases)
    func theSharedCases(_ fixture: Case) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: Self.file.timeZone))
        let start = try #require(ISO8601DateFormatter().date(from: fixture.run.start))
        let size: RunSize = fixture.run.km.map(RunSize.km) ?? .minutes(fixture.run.minutes)
        let run = PlannedRun(key: fixture.name, title: "", calendarTitle: "", start: start,
                             end: start.addingTimeInterval(fixture.run.minutes * 60), size: size,
                             isHard: fixture.run.hard ?? false, isAllDay: false)
        let history = fixture.history.map { past -> Workout in
            let begin = calendar.date(byAdding: .day, value: -past.daysBack, to: start)!
            let minutes = past.minutes ?? (past.km ?? 0) * 6
            return Workout(id: "\(past.daysBack)-\(past.km ?? 0)", activityType: past.type ?? "Running", start: begin,
                           end: begin.addingTimeInterval(minutes * 60), effort: nil, avgHeartRate: nil,
                           source: .health, distanceKm: past.km)
        }
        let injury = fixture.injuryMonth.flatMap { month -> Date? in
            let parts = month.split(separator: "-").compactMap { Int($0) }
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        }
        let got = GuardrailRule.flag(for: run, .init(history: history, injuryMonth: injury,
                                                     check: fixture.check.flatMap(MorningCheck.init(rawValue:)),
                                                     upcoming: [], calendar: calendar,
                                                     body: fixture.bodyOff == true ? BodySignalTests.off : nil,
                                                     loadCeiling: fixture.loadCeiling))
        guard let want = fixture.expect else {
            #expect(got == nil)
            return
        }
        let flag = try #require(got)
        #expect(flag.kind.rawValue == want.kind)
        #expect(flag.suggested.value == want.suggested)
        #expect(flag.longest30?.value == want.longest30)
        #expect(flag.keepEasy == want.keepEasy)
        #expect(flag.injuryAdjusted == want.injuryAdjusted)
    }
}
