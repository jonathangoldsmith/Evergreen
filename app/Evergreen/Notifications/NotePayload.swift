import Foundation

/// What a guardrail notification carries in its userInfo: the whole run and
/// flag, because Apple Health can't be read while the phone is locked, so the
/// action records the decision without re-running the rule (plan item 7).
struct NotePayload: Codable, Sendable {
    var run: PlannedRun?
    var flag: GuardrailFlag?
    var weekStart: Date?

    static let key = "guardrail"

    func userInfo() -> [String: Any] {
        guard let data = try? JSONEncoder.contract.encode(self) else { return [:] }
        return [Self.key: data, "open": "today"]
    }

    init(run: PlannedRun? = nil, flag: GuardrailFlag? = nil, weekStart: Date? = nil) {
        self.run = run
        self.flag = flag
        self.weekStart = weekStart
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let data = userInfo[Self.key] as? Data,
              let payload = try? JSONDecoder.contract.decode(NotePayload.self, from: data) else { return nil }
        self = payload
    }
}
