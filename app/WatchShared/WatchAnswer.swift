import Foundation

/// A tap on the watch, sent to the phone (range plan item 19): right away when
/// the phone is reachable, otherwise queued with `transferUserInfo`. The phone
/// records it as the same decision as a Lock Screen tap, or drops it if the run
/// has started or was already decided.
struct WatchAnswer: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case fresh, tired, sore, accept, keep }

    var id: String
    var runKey: String
    var kind: Kind
    var at: Date

    static let key = "answer"

    func encoded() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [Self.key: data]
    }

    init(runKey: String, kind: Kind, at: Date = Date()) {
        id = UUID().uuidString
        self.runKey = runKey
        self.kind = kind
        self.at = at
    }

    init?(_ dictionary: [String: Any]) {
        guard let data = dictionary[Self.key] as? Data,
              let answer = try? JSONDecoder().decode(WatchAnswer.self, from: data) else { return nil }
        self = answer
    }
}
