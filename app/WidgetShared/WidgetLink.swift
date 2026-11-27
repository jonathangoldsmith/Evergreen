import Foundation

/// What a tap on the phone widget opens (widgets, TODOS item 1). A widget
/// button can't run the app's code, so each answer opens Evergreen with the
/// answer in the URL and the app records it exactly like a watch tap: one
/// decision, the calendar, the notifications and the audit record all go
/// through `handleWatchAnswer`.
///
/// An answer link carries a token only the app and its widget can read (it
/// lives in the App Group), so a web page or another app can't answer for the
/// person with a crafted `evergreen://` link. Opening Today needs no token.
enum WidgetLink: Equatable, Sendable {
    case today
    case answer(runKey: String, kind: WatchAnswer.Kind)

    static let scheme = "evergreen"
    static let tokenKey = "widget_link_token"

    static var sharedDefaults: UserDefaults { UserDefaults(suiteName: WatchStateStore.appGroup) ?? .standard }

    func url(token: String?) -> URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .today:
            components.host = "today"
        case .answer(let runKey, let kind):
            components.host = "answer"
            components.queryItems = [
                URLQueryItem(name: "run", value: runKey),
                URLQueryItem(name: "kind", value: kind.rawValue),
                URLQueryItem(name: "token", value: token ?? ""),
            ]
        }
        return components.url ?? URL(string: "\(Self.scheme)://today")!
    }

    /// nil for a URL that isn't ours, or an answer whose token doesn't match.
    init?(url: URL, token: String?) {
        guard url.scheme == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch components.host {
        case "today":
            self = .today
        case "answer":
            guard let token, !token.isEmpty, value("token") == token,
                  let runKey = value("run"), !runKey.isEmpty,
                  let kind = value("kind").flatMap(WatchAnswer.Kind.init(rawValue:)) else { return nil }
            self = .answer(runKey: runKey, kind: kind)
        default:
            return nil
        }
    }

    /// The token the widget puts in its links; nil until the app has made one.
    static func token(in defaults: UserDefaults = sharedDefaults) -> String? {
        defaults.string(forKey: tokenKey)
    }

    /// The app makes the token once and keeps it.
    @discardableResult
    static func ensureToken(in defaults: UserDefaults = sharedDefaults) -> String {
        if let token = token(in: defaults), !token.isEmpty { return token }
        let token = UUID().uuidString + UUID().uuidString
        defaults.set(token, forKey: tokenKey)
        return token
    }
}
