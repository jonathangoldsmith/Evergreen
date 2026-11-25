import Foundation
import Testing
@testable import Evergreen

/// The app's side of the buddy (range plan item 22): requests, kind words for
/// refusals, and the Amplitude event.
struct BuddyClientTests {
    static let client = BuddyClient(baseURL: URL(string: "https://harness.example")!, secret: "s",
                                    user: "usr_0123456789abcdef")

    @Test func routesAndBodies() throws {
        let invite = Self.client.request("POST", "buddy", ["displayName": "Alex"])
        #expect(invite.url?.absoluteString == "https://harness.example/users/usr_0123456789abcdef/buddy")
        #expect(invite.httpMethod == "POST" && invite.value(forHTTPHeaderField: "X-Harness-Secret") == "s")
        let body = try #require(invite.httpBody)
        #expect(try JSONDecoder().decode([String: String].self, from: body) == ["displayName": "Alex"])

        let redeem = Self.client.request("POST", "buddy/redeem", ["code": "ABCD2345"])
        #expect(redeem.url?.path() == "/users/usr_0123456789abcdef/buddy/redeem")
        let token = Self.client.request("PUT", "push-token", ["token": "ab", "environment": "sandbox"])
        #expect(token.url?.path() == "/users/usr_0123456789abcdef/push-token" && token.httpMethod == "PUT")
    }

    @Test(arguments: ["expired", "used", "already_paired", "own_code", "unknown_code", "too_many_tries", "bad_name", "anything"])
    func everyRefusalIsSaidKindly(reason: String) {
        let words = BuddyCopy.refusal(reason)
        #expect(!words.isEmpty && !words.contains("_"))
    }

    @Test func theStatusDecodesWithoutIds() throws {
        let json = #"{"status":"paired","role":"friend","buddyName":"Alex","yourName":null,"pairedAt":"2026-11-25T09:00:00Z","notes":[{"text":"Alex did a 15-minute walk.","activityType":"Walking","minutes":15,"at":"2026-11-25T18:45:00-08:00"}]}"#
        let status = try JSONDecoder().decode(BuddyClient.Status.self, from: Data(json.utf8))
        #expect(status.buddyName == "Alex" && status.notes?.first?.text == "Alex did a 15-minute walk.")
    }

    @Test func theBuddyAmplitudeEventIsWordsOnly() {
        #expect(AnalyticsEvent.buddy("paired").properties == ["action": "paired"])
        #expect(AnalyticsEvent.buddy("anything").properties == ["action": "unpaired"])
        #expect(AnalyticsEvent.comebackBooked.properties.isEmpty && AnalyticsEvent.comebackDone.properties.isEmpty)
    }
}
