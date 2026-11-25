import Foundation
import SwiftData

/// One week's pain answer (plan item 17), with its OSTRC answers after
/// "A little" or "Yes" (business notes BN1). The body part stays on the phone.
/// Its own model, never an ActionRecord, so it never reaches the feed.
@Model
final class PainRecord {
    /// Monday 00:00 local time of the week asked about.
    var weekStart: Date
    var answerRaw: String
    /// The four OSTRC answer codes, comma-separated; empty when not given.
    var ostrcText: String = ""
    var bodyPart: String?
    var createdAt: Date

    init(weekStart: Date, answer: PainAnswer, at date: Date) {
        self.weekStart = weekStart
        answerRaw = answer.rawValue
        createdAt = date
    }

    var answer: PainAnswer { PainAnswer(rawValue: answerRaw) ?? .noAnswer }

    var ostrc: [Int]? {
        get {
            let codes = ostrcText.split(separator: ",").compactMap { Int($0) }
            return codes.count == OSTRC.questions.count ? codes : nil
        }
        set { ostrcText = newValue?.map(String.init).joined(separator: ",") ?? "" }
    }
}
