import Foundation
import Testing
@testable import Evergreen

/// The coach link (range plan item 20): where it points and what the app sends.
struct CoachClientTests {
    static let client = CoachClient(baseURL: URL(string: "https://harness.example")!, secret: "s",
                                    user: "usr_0123456789abcdef")

    @Test func theLinkIsThePublicCoachPage() {
        #expect(Self.client.link(for: "abc_DEF-123").absoluteString == "https://harness.example/coach#abc_DEF-123")
    }

    @Test func createSendsTheNameAndTheTick() throws {
        let request = Self.client.request("POST", "coach-shares", ["displayName": .string("Sam"), "includeFeelings": .bool(true)])
        #expect(request.url?.path() == "/users/usr_0123456789abcdef/coach-shares")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: Any]
        #expect(body?["displayName"] as? String == "Sam" && body?["includeFeelings"] as? Bool == true)
    }

    @Test func editAndRevokeAddressOneShare() {
        #expect(Self.client.request("PATCH", "coach-shares/abc", ["renew": .bool(true)]).url?.path()
                == "/users/usr_0123456789abcdef/coach-shares/abc")
        #expect(Self.client.request("DELETE", "coach-shares/abc").httpMethod == "DELETE")
    }

    @Test func aFlagEventNamesItsRunForTheCoachPage() {
        let event = UploadEvent.flag(GuardrailCopyTests.flags[0], run: GuardrailCopyTests.run, at: Fixture.at(19),
                                     calendar: Fixture.calendar)
        #expect(event.run == GuardrailCopyTests.run.swapItemId)
    }
}
