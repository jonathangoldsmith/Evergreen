import Foundation
import Testing

/// Wellness wording (business notes BN3, range plan B3): no app screen,
/// notification, watch face or permission prompt says "safe", "prevent",
/// "risk" or "injury-proof". This reads the app's source from the repo (the
/// simulator can see it) and checks every string literal and plist.
struct WordingTests {
    // Computed: Regex isn't Sendable, so it can't be a static constant in Swift 6.
    static var banned: Regex<AnyRegexOutput> {
        try! Regex(#"\b(safe(ly|r|st|ty)?|unsafe|prevent\w*|risk\w*|injury[- ]?proof)\b"#).ignoresCase()
    }
    static var literal: Regex<AnyRegexOutput> { try! Regex(#""(?:[^"\\\n]|\\.)*""#) }

    /// app/, found from this file's place in the repo.
    static let appFolder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    static func files(_ ext: String) -> [URL] {
        let walker = FileManager.default.enumerator(at: appFolder, includingPropertiesForKeys: nil)
        return (walker?.allObjects as? [URL] ?? []).filter {
            $0.pathExtension == ext && !$0.path.contains("Tests/") && !$0.path.contains("/Build/")
        }
    }

    @Test func noShownStringMakesASafetyClaim() throws {
        let sources = Self.files("swift")
        try #require(sources.count > 50, "Couldn't find the app's source from \(Self.appFolder.path)")
        var found: [String] = []
        for file in sources {
            let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            for (number, line) in lines.enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                for match in line.matches(of: Self.literal) where line[match.range].contains(Self.banned) {
                    found.append("\(file.lastPathComponent):\(number + 1) \(line[match.range])")
                }
            }
        }
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }

    @Test func noPermissionPromptOrSettingMakesASafetyClaim() throws {
        let plists = Self.files("plist") + Self.files("strings")
        try #require(!plists.isEmpty)
        let found = try plists.filter { try String(contentsOf: $0, encoding: .utf8).contains(Self.banned) }
        #expect(found.isEmpty, "\(found.map(\.lastPathComponent))")
    }
}
