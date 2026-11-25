import CryptoKit
import Foundation

/// A short hash that stays the same across launches (Swift's `hashValue` doesn't).
enum StableHash {
    static func hex(_ text: String, length: Int = 16) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(length))
    }
}
