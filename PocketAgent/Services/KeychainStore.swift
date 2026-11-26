import Foundation
import Security

enum KeychainStore {
    private static let service = "com.pocketagent.credentials"

    // Endpoint-scoped entries prevent automatic credential reuse after a server change.
    // Legacy unscoped keys are intentionally not migrated to an unverified endpoint.
    private static func scoped(_ account: String) -> String {
        guard account == SettingsKeys.apiKey else { return account }
        let base = UserDefaults.standard.string(forKey: SettingsKeys.baseURL) ?? ""
        let endpoint = ResponsesModelClient.endpoint(baseURL: base)?.absoluteString ?? base
        return account + ":" + endpoint
    }

    static func save(_ value: String, for account: String) {
        delete(account)
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: scoped(account),
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: scoped(account),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: scoped(account)
        ]
        SecItemDelete(query as CFDictionary)
    }
}
