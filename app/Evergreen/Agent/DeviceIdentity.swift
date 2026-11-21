import Foundation

/// This install's anonymous id on Evergreen's planner: "usr_" and 16 hex
/// characters, an HMAC under the per-install secret in the Keychain (the same
/// secret the memory agent's ids use). It carries no name or account, and a
/// reinstall makes a new one. The harness keeps the person's Apple Health
/// history under it until they delete it (Your data).
enum DeviceIdentity {
    static let userId: String = id(secret: IdSecret.load())

    static func id(secret: String) -> String {
        "usr_" + MemoryFiles.hmac(secret, "device\u{0}planner").prefix(16)
    }
}
