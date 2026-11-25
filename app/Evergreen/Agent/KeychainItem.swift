import Foundation
import Security

/// One string in this device's Keychain, readable after the first unlock
/// (so background wakes can use it) and never synced off the device.
struct KeychainItem: Sendable {
    let account: String

    func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String) {
        delete()
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account] as CFDictionary)
    }
}
