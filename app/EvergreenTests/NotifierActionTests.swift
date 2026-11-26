import Foundation
import SwiftData
import Testing
@testable import Evergreen

/// Lock Screen buttons (plan items 7 and 17, task E7): each records exactly
/// one decision, the first answer wins, and pain answers go to their own
/// model, never the action log.
@MainActor
struct NotifierActionTests {
    /// Containers live as long as the test run: a context outlived by its
    /// container crashes on its next fetch.
    static var containers: [ModelContainer] = []

    static func model() throws -> AppModel {
        let container = try Storage.open(at: StorageTests.tempStore())
        containers.append(container)
        let model = AppModel(context: container.mainContext)
        // Off the real calendar, so the runs a test sets aren't replaced on save.
        model.calendarSync.accessForTesting = .notAsked
        return model
    }

    /// Two days from now, in whole seconds like a calendar event (ISO 8601 in the payload drops fractions).
    static let start = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 2 * 86_400).rounded())
    static let run = PlannedRun(key: "runna|2030-06-02|Long run 18 km", title: "Long run 18 km", calendarTitle: "Runna",
                                start: start, end: start.addingTimeInterval(5400),
                                size: .km(18), isHard: false, isAllDay: false)
    static let flag = GuardrailFlag(kind: .spike, planned: .km(18), suggested: .km(13), longest30: .km(13),
                                    keepEasy: false, injuryAdjusted: false)
    static let payload = NotePayload(run: run, flag: flag)

    @Test func makeItRecordsOneSwapAndASecondAnswerIsIgnored() async throws {
        let model = try Self.model()
        await model.handleNotificationAction(.swapAccept, Self.payload)
        await model.handleNotificationAction(.swapAccept, Self.payload)
        await model.handleNotificationAction(.swapKeep, Self.payload)

        #expect(model.decisions.map(\.choice) == [.accept])
        #expect(model.swapItems.map(\.id) == [Self.run.swapItemId])
        #expect(model.swapItems.first?.slot.start == Self.run.start)
        #expect(model.swapTitles[Self.run.swapItemId] == "Easy run 13 km (was 18 km)")
    }

    @Test func undoFromTheLockScreenKeepsThePlan() async throws {
        let model = try Self.model()
        await model.handleNotificationAction(.swapAccept, Self.payload)
        await model.handleNotificationAction(.swapUndo, Self.payload)

        #expect(model.decision(for: Self.run)?.choice == .keep)
        #expect(model.swapItems.isEmpty)
    }

    @Test func thePayloadSurvivesTheNotificationsUserInfo() throws {
        let decoded = try #require(NotePayload(userInfo: Self.payload.userInfo()))
        #expect(decoded.run == Self.run && decoded.flag == Self.flag)
    }

    @Test func aMorningAnswerIsRecordedOnce() async throws {
        let model = try Self.model()
        await model.handleNotificationAction(.checkSore, NotePayload(run: Self.run))
        await model.handleNotificationAction(.checkFresh, NotePayload(run: Self.run))
        #expect(model.checkIns.map(\.answer) == [.sore])
    }

    @Test func noIsAZeroOSTRCWeekAndNeverReachesTheActionLog() async throws {
        let model = try Self.model()
        let week = PainWeek.monday(of: Date(), calendar: .current)
        await model.handleNotificationAction(.painNo, NotePayload(weekStart: week))

        let record = try #require(model.painRecord(for: week))
        #expect(record.answer == .no && record.ostrc == OSTRC.noProblem)
        #expect(model.ostrcWeek == nil)
        #expect(model.appliedActions.isEmpty)
    }

    @Test func yesSetsTheInjuryMonthAndAsksTheOSTRCQuestions() async throws {
        let model = try Self.model()
        let week = PainWeek.monday(of: Date(), calendar: .current)
        await model.handleNotificationAction(.painYes, NotePayload(weekStart: week))

        #expect(model.painRecord(for: week)?.answer == .yes)
        #expect(model.profile.injuryMonth != nil)
        #expect(model.ostrcWeek == week)

        model.saveOSTRC([2, 1, 1, 2], bodyPart: "Knee", week: week)
        let record = try #require(model.painRecord(for: week))
        #expect(record.ostrc == [2, 1, 1, 2] && record.bodyPart == "Knee")
        #expect(model.ostrcWeek == nil)
    }
}
