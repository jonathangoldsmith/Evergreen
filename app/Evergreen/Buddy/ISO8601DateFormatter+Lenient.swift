import Foundation

extension ISO8601DateFormatter {
    /// Reads the harness's timestamps, with or without fractional seconds.
    nonisolated(unsafe) static let lenient: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
