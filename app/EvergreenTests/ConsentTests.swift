import Foundation
import SwiftData
import Testing
@testable import Evergreen

/// "What leaves your phone" (business notes BN2, range plan B2): nothing goes
/// to the harness or Amplitude before a "yes", and "Keep it on my phone"
/// leaves the outbox empty.
@MainActor
struct ConsentTests {
    static let run = GuardrailCopyTests.run
    static let flag = GuardrailCopyTests.flags[0]

    @Test func notAskedYetCountsAsNo() throws {
        let model = try NotifierActionTests.model()
        #expect(model.profile.uploadsAllowed == nil)
        #expect(!model.mayUpload)
        model.upload(.flag(Self.flag, run: Self.run, at: Fixture.at(19), calendar: Fixture.calendar), ownAnswer: true)
        #expect(model.outbox.pending.isEmpty)
        // The planner's request carries no ID or Health history, and the planner isn't offered.
        let request = model.plannerRequest()
        #expect(request.user == nil && request.history == nil)
        #expect(!model.plannerAvailable)
    }

    @Test func withoutAYesTheAgentStaysOnThePhone() {
        let agent = AgentChoice.current(uploadsAllowed: false)
        let standIn = try? #require(agent as? StandInAgent)
        #expect(standIn?.recommend == nil)
        #expect(standIn?.evidence == nil)
    }

    @Test func researchIsOffByDefault() {
        #expect(Profile().researchAllowed == false)
    }

    @Test func keepingItOnThePhoneEmptiesTheOutbox() throws {
        let model = try NotifierActionTests.model()
        model.setConsent(uploads: true, research: true)
        // The "yes" is the first event; no harness is set in tests, so it waits.
        #expect(model.outbox.pending.count == 1)
        model.setConsent(uploads: false, research: true)
        #expect(model.outbox.pending.isEmpty)
        #expect(!model.profile.researchAllowed)   // research never without uploads
        model.upload(.checkIn(.sore, run: Self.run, at: Fixture.at(9), calendar: Fixture.calendar), ownAnswer: true)
        #expect(model.outbox.pending.isEmpty)
    }

    @Test func theOutboxSendsNothingWhileUploadsAreOff() async throws {
        let harness = EventOutboxTests.FakeHarness()
        harness.online = true
        let outbox = EventOutbox(context: try EventOutboxTests.context()) { { try await harness.send($0) } }
        var allowed = false
        outbox.isAllowed = { allowed }
        outbox.enqueue(.flag(Self.flag, run: Self.run, at: Fixture.at(19), calendar: Fixture.calendar))

        #expect(await outbox.flush() == 0)
        #expect(harness.calls == 0)
        #expect(outbox.pending.count == 1)

        allowed = true
        #expect(await outbox.flush() == 1)
        #expect(harness.calls == 1)
    }

    @Test func pairingWithUploadsOffIsRefusedWithoutAsking() async throws {
        let model = try NotifierActionTests.model()
        model.setConsent(uploads: false, research: false)
        #expect(await model.redeemBuddy(code: "ABCDEFGH") == .refused("uploads_off"))
        if case .failure(let failure) = await model.inviteBuddy(name: "Alex") {
            #expect(failure == .refused("uploads_off"))
        } else {
            Issue.record("An invite was made with uploads off")
        }
        // Consent isn't switched on behind the person's back; only "Allow and share" does that.
        #expect(model.profile.uploadsAllowed == false)
        #expect(model.coachClient == nil)
    }
}
