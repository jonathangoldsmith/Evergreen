import Foundation
import SwiftData

/// A morning answer (Fresh / Tired / Sore) for one planned run, kept across days.
@Model
final class CheckInRecord {
    var runKey: String
    var answerRaw: String
    var createdAt: Date

    init(runKey: String, answer: MorningCheck, at date: Date) {
        self.runKey = runKey
        answerRaw = answer.rawValue
        createdAt = date
    }

    var answer: MorningCheck { MorningCheck(rawValue: answerRaw) ?? .fresh }
}
