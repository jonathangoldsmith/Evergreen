import Foundation
import Testing
@testable import Evergreen

/// The harness's shoe pick (harness/INTEGRATION.md): when the client is on,
/// what it sends, and that the harness's answer decodes as the app's Purchase.
/// No network.
struct RecommendClientTests {
    static func defaults(_ values: [String: String]) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "recommend-\(UUID().uuidString)")!
        for (key, value) in values { defaults.set(value, forKey: key) }
        return defaults
    }

    /// A bundle with no Info.plist, so a secret built into the app doesn't leak in.
    static let bare = Bundle(url: FileManager.default.temporaryDirectory)!

    @Test func offWithoutASecret() {
        #expect(RecommendClient.configured(defaults: Self.defaults([:]), bundle: Self.bare) == nil)
        #expect(RecommendClient.configured(defaults: Self.defaults(["recommend_url": "https://example.com"]),
                                           bundle: Self.bare) == nil)
    }

    @Test func aSecretAloneUsesTheDeployedHarness() throws {
        let client = try #require(RecommendClient.configured(defaults: Self.defaults(["harness_secret": " s3cret "]),
                                                             bundle: Self.bare))
        #expect(client.baseURL == RecommendClient.defaultURL)
        #expect(client.secret == "s3cret")
    }

    @Test func theSettingsURLWinsAndMustBeHTTP() throws {
        let local = try #require(RecommendClient.configured(
            defaults: Self.defaults(["harness_secret": "s", "recommend_url": "http://localhost:8000"]), bundle: Self.bare))
        #expect(local.baseURL.absoluteString == "http://localhost:8000")
        #expect(RecommendClient.configured(
            defaults: Self.defaults(["harness_secret": "s", "recommend_url": "ftp://x"]), bundle: Self.bare) == nil)
    }

    /// The harness counts delivery from midnight in `now`'s offset, so the phone
    /// sends local time and local days, not UTC.
    @Test func datesGoOutInThePersonsTimeZone() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let evening = cal.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 18, minute: 45))!
        #expect(RecommendClient.instant(evening, cal) == "2026-11-19T18:45:00-08:00")
        #expect(RecommendClient.day(evening, cal) == "2026-11-19")
    }

    /// The `purchase` from INTEGRATION.md §4, trimmed: offsets on dates, extra keys ignored.
    @Test func theHarnessAnswerDecodesAsAPurchase() throws {
        let json = """
        {"id": "shoes-2026-10-22", "item": "New Balance Fresh Foam X 1080 v15", "merchant": "Demo store, no charge",
         "amountCents": 17000, "status": "awaitingApproval",
         "rule": {"id": "ask-first", "text": "Ask me before buying anything else."},
         "noticed": "Your shoes hit 390 miles (97% of their life). Race day is in 9 days.",
         "evidence": [{"source": "Running shoe care guide", "passage": "Replace every 300 to 500 miles."}],
         "evidenceLive": true,
         "options": [{"name": "New Balance Fresh Foam X 1080 v15", "amountCents": 17000, "arrives": "2026-11-23T00:00:00-08:00"},
                     {"name": "Altra Paradigm 8", "amountCents": 10300, "arrives": "2026-11-23T00:00:00-08:00",
                      "lostBecause": "Less cushion for long runs"}],
         "extra": "ignored"}
        """
        let purchase = try JSONDecoder.contract.decode(Purchase.self, from: Data(json.utf8))
        #expect(purchase.status == .awaitingApproval)
        #expect(purchase.evidenceLive)
        #expect(purchase.options.count == 2)
        #expect(purchase.options[0].arrives == ISO8601DateFormatter().date(from: "2026-11-23T08:00:00Z"))
        #expect(purchase.options[1].lostBecause == "Less cushion for long runs")
        #expect(purchase.photoURL == nil)
    }

    /// The harness sends a product photo on the purchase and on each option; the pick shows it.
    @Test func theHarnessPhotoComesThrough() throws {
        let json = """
        {"id": "shoes-2026-10-22", "item": "ASICS Gel-Cumulus 27", "merchant": "Demo store, no charge",
         "amountCents": 14000, "status": "awaitingApproval",
         "rule": {"id": "ask-first", "text": "Ask me before buying anything else."},
         "noticed": "Your shoes hit 390 miles.", "evidence": [], "evidenceLive": false,
         "imageUrl": "https://example.com/cumulus.jpeg",
         "options": [{"name": "ASICS Gel-Cumulus 27", "amountCents": 14000, "imageUrl": "https://example.com/cumulus.jpeg"},
                     {"name": "Altra Paradigm 8", "amountCents": 10300, "imageUrl": "https://example.com/paradigm.jpg"}]}
        """
        var purchase = try JSONDecoder.contract.decode(Purchase.self, from: Data(json.utf8))
        #expect(purchase.photoURL?.absoluteString == "https://example.com/cumulus.jpeg")
        #expect(purchase.options[1].imageUrl == "https://example.com/paradigm.jpg")

        // Only the option has one: still shown.
        purchase.imageUrl = nil
        #expect(purchase.photoURL?.absoluteString == "https://example.com/cumulus.jpeg")

        // It survives the app's own storage round trip.
        let again = try JSONDecoder.contract.decode(Purchase.self, from: JSONEncoder.contract.encode(purchase))
        #expect(again.options[0].imageUrl == "https://example.com/cumulus.jpeg")
    }
}
