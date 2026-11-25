import Foundation
import Testing
@testable import Evergreen

/// The brake's words: the card, the notes, and the wellness-only rule
/// (business notes BN3): never "safe", "prevent", "risk" or "injury-proof".
struct GuardrailCopyTests {
    static let now = Fixture.at(19, dayOffset: 2)                    // Saturday 7 PM
    static let run = PlannedRun(key: "runna|2026-11-22|Long run 18 km", title: "Long run 18 km", calendarTitle: "Runna",
                                start: Fixture.at(8, dayOffset: 3), end: Fixture.at(10, dayOffset: 3),
                                size: .km(18), isHard: false, isAllDay: false)

    static let flags: [GuardrailFlag] = [
        GuardrailFlag(kind: .spike, planned: .km(18), suggested: .km(13), longest30: .km(13), keepEasy: false, injuryAdjusted: false),
        GuardrailFlag(kind: .returnSpike, planned: .km(8), suggested: .km(5), longest30: nil, keepEasy: false, injuryAdjusted: true),
        GuardrailFlag(kind: .sore, planned: .km(18), suggested: .km(12), longest30: nil, keepEasy: false, injuryAdjusted: false),
        GuardrailFlag(kind: .sore, planned: .minutes(22), suggested: .minutes(22), longest30: nil, keepEasy: true, injuryAdjusted: false),
        GuardrailFlag(kind: .tired, planned: .minutes(45), suggested: .minutes(35), longest30: nil, keepEasy: false, injuryAdjusted: false),
    ]

    @Test func theSpikeCardCitesTheJumpAndTheLongestRun() {
        let flag = Self.flags[0]
        #expect(GuardrailCopy.question(Self.run, flag, now: Self.now, calendar: Fixture.calendar) == "Make tomorrow’s run 13 km?")
        #expect(GuardrailCopy.reason(flag) == "18 km is 38% past your longest run this month (13 km).")
        #expect(GuardrailCopy.accept(flag) == "Make it 13 km")
        #expect(GuardrailCopy.keep(flag) == "Keep 18 km")
        #expect(GuardrailCopy.sourceNote(Self.run, flag.planned) == "Runna will still say 18 km.")
    }

    @Test func theEveningNoteMatchesDesignDecisionTen() {
        let note = GuardrailCopy.spikeNote(Self.run, Self.flags[0], now: Self.now, calendar: Fixture.calendar)
        #expect(note.body == "Tomorrow’s 18 km is a big jump from your longest run (13 km). Make it 13?")
    }

    @Test func aSmallCutAsksToRunItEasy() {
        let flag = Self.flags[3]
        #expect(GuardrailCopy.question(Self.run, flag, now: Self.now, calendar: Fixture.calendar) == "Run tomorrow’s 22 min easy?")
        #expect(GuardrailCopy.accept(flag) == "Run it easy")
    }

    @Test func noBrakeCopyMakesASafetyClaim() {
        let banned = ["safe", "prevent", "risk", "injury-proof", "injury proof"]
        var lines = [GuardrailCopy.morningCheck.title, GuardrailCopy.morningCheck.body]
        for flag in Self.flags {
            lines += [
                GuardrailCopy.question(Self.run, flag, now: Self.now), GuardrailCopy.reason(flag),
                GuardrailCopy.accept(flag), GuardrailCopy.keep(flag), GuardrailCopy.sourceNote(Self.run, flag.planned),
                GuardrailCopy.spikeNote(Self.run, flag, now: Self.now).body, GuardrailCopy.spoken(Self.run, flag, now: Self.now),
            ]
        }
        for line in lines {
            for word in banned {
                #expect(!line.lowercased().contains(word), "“\(line)” says “\(word)”")
            }
        }
    }

    @Test func sizesReadPlainly() {
        #expect(RunSize.minutes(110.5).label == "111 min")
        #expect(RunSize.km(12.5).label == "12.5 km")
        #expect(RunSize.km(13).label == "13 km")
    }
}
