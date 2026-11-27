import Foundation
import Testing
@testable import Evergreen

/// Readiness (TODOS item 2): which of this morning's readings are off the
/// person's usual, how much history that needs, and the words for it.
struct BodySignalTests {
    /// Resting heart rate 7 over and sleep 1h 50 under: off.
    static let off = BodySignal(off: [
        .init(reading: .restingHeartRate, now: 56, usual: 49),
        .init(reading: .sleep, now: 340, usual: 450),
    ])

    static let calendar = Fixture.calendar
    static let today = Fixture.storyDay

    /// 60 usual days before today (resting 49, 7h 30 asleep, HRV 62 ms), then today.
    static func days(history: Int = 60, resting: Double? = 49, sleep: Double? = 450, hrv: Double? = 62,
                     recentHRV: Double? = nil) -> [HealthHistory.Day] {
        var days = (1...history).map { back -> HealthHistory.Day in
            let date = calendar.date(byAdding: .day, value: -back, to: today)!
            // The last 6 days before today carry the recent HRV when one is given.
            return HealthHistory.Day(date: date, sleepMin: 450, restingHeartRate: 49,
                                     hrv: back < BodySignal.hrvRecentDays ? (recentHRV ?? 62) : 62)
        }
        days.append(HealthHistory.Day(date: today, sleepMin: sleep, restingHeartRate: resting, hrv: recentHRV ?? hrv))
        return days
    }

    static func read(_ days: [HealthHistory.Day]) -> BodySignal {
        BodySignal.read(days, on: calendar.date(bySettingHour: 7, minute: 0, second: 0, of: today)!, calendar: calendar)
    }

    // MARK: Readings

    @Test func aUsualMorningIsNotOff() {
        let signal = Self.read(Self.days())
        #expect(signal.off.isEmpty)
        #expect(!signal.isOff)
    }

    @Test func restingHeartRateAndShortSleepAreOff() throws {
        let signal = Self.read(Self.days(resting: 55, sleep: 340))
        #expect(signal.isOff)
        #expect(signal.off.map(\.reading) == [.restingHeartRate, .sleep])
        let resting = try #require(signal.off.first)
        #expect(resting.now == 55 && resting.usual == 49)
    }

    @Test func justUnderEachThresholdIsNotOff() {
        // 4 bpm over, 55 minutes short, HRV 8% under.
        let signal = Self.read(Self.days(resting: 53, sleep: 395, recentHRV: 57))
        #expect(signal.off.isEmpty)
    }

    @Test func oneReadingOffIsNotEnough() {
        let signal = Self.read(Self.days(resting: 60))
        #expect(signal.off.map(\.reading) == [.restingHeartRate])
        #expect(!signal.isOff)
    }

    @Test func hrvUsesTheSevenDayAverage() {
        // A week at 52 ms against a usual of 62: 16% under.
        let week = Self.read(Self.days(recentHRV: 52))
        #expect(week.off.map(\.reading) == [.hrv])
        // One low morning alone doesn't move the 7-day average enough.
        let oneMorning = Self.read(Self.days(hrv: 40))
        #expect(oneMorning.off.isEmpty)
    }

    @Test func allThreeOff() {
        let signal = Self.read(Self.days(resting: 56, sleep: 330, recentHRV: 50))
        #expect(signal.off.map(\.reading) == [.restingHeartRate, .sleep, .hrv])
        #expect(signal.isOff)
    }

    @Test func withoutTwoWeeksOfHistoryNothingCounts() {
        let signal = Self.read(Self.days(history: 10, resting: 70, sleep: 200, recentHRV: 30))
        #expect(signal.off.isEmpty)
    }

    @Test func aMissingReadingTodayIsLeftOut() {
        let signal = Self.read(Self.days(resting: nil, sleep: 330))
        #expect(signal.off.map(\.reading) == [.sleep])
    }

    @Test func hrvNeedsThreeRecentReadings() {
        var days = Self.days(recentHRV: 40)
        // Keep only today's and yesterday's recent HRV.
        for i in days.indices where days[i].date >= Self.calendar.date(byAdding: .day, value: -6, to: Self.today)!
            && days[i].date < Self.calendar.date(byAdding: .day, value: -1, to: Self.today)! {
            days[i].hrv = nil
        }
        #expect(Self.read(days).off.isEmpty)
    }

    // MARK: Words

    @Test func theCardSaysWhichReadingsAndByHowMuch() {
        #expect(GuardrailCopy.bodyReadings(Self.off)
                == "Your resting heart rate is 7 bpm above your usual and you slept 5h 40 instead of your usual 7h 30")
        let hrv = BodySignal(off: [.init(reading: .hrv, now: 52, usual: 62), .init(reading: .sleep, now: 360, usual: 420)])
        #expect(GuardrailCopy.bodyReadings(hrv)
                == "Your heart rate variability is 16% under your usual and you slept 6h instead of your usual 7h")
    }

    @Test func theReasonAndTheQuestion() {
        let flag = GuardrailFlag(kind: .body, planned: .minutes(100), suggested: .minutes(80), longest30: nil,
                                 keepEasy: false, injuryAdjusted: false, body: Self.off)
        #expect(GuardrailCopy.reason(flag).hasSuffix("instead of your usual 7h 30, and this one is long or hard."))
        var easy = flag
        easy.keepEasy = true
        easy.suggested = .minutes(100)
        #expect(GuardrailCopy.reason(easy).hasSuffix(". Keep the distance and run it easy."))
    }

    @Test func theLockScreenNamesTheReadingsWithoutNumbers() {
        let run = PlannedRun(key: "k", title: "Long run 1h 40", calendarTitle: "Runna", start: Fixture.at(18),
                             end: Fixture.at(19, 40), size: .minutes(100), isHard: false, isAllDay: false)
        let flag = GuardrailFlag(kind: .body, planned: .minutes(100), suggested: .minutes(80), longest30: nil,
                                 keepEasy: false, injuryAdjusted: false, body: Self.off)
        let note = GuardrailCopy.spikeNote(run, flag, now: Fixture.at(7), calendar: Fixture.calendar)
        #expect(note.body == "Your resting heart rate and sleep are off your usual this morning. Make it 80 min?")
        #expect(!note.body.contains { $0.isNumber && !"80".contains($0) })
    }

    @Test func noSafetyWords() {
        let flag = GuardrailFlag(kind: .body, planned: .minutes(100), suggested: .minutes(80), longest30: nil,
                                 keepEasy: false, injuryAdjusted: false, body: Self.off)
        let words = GuardrailCopy.reason(flag).lowercased()
        for banned in ["safe", "injur", "recover", "risk", "prevent"] {
            #expect(!words.contains(banned), "\(banned)")
        }
    }

    @Test func sleepLabels() {
        #expect(GuardrailCopy.sleepLabel(340) == "5h 40")
        #expect(GuardrailCopy.sleepLabel(420) == "7h")
        #expect(GuardrailCopy.sleepLabel(448) == "7h 30")
    }

    @Test func theAmplitudeEventSaysBodyOnly() {
        #expect(AnalyticsEvent.flagShown(.body).properties == ["kind": "body"])
    }
}
